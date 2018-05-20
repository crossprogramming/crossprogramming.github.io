---
layout: post
title: "Controlling service startup order in Docker Compose"
date: 2018-05-13 16:02:29 +0300
tags: [programming, docker, docker-compose, docker-healthcheck, jq, windows]
---
- [Context](#context)
- [Solution #1: Use depends_on, condition and service_healthy](#service_healthy)
- [Solution #2: Port checking with a twist](#port-checking)
- [Solution #3: Invoke Docker Engine API](#docker_engine_api)
- [Conclusion](#conclusion)
- [Bonus](#bonus)
  - [Maven Assembly plugin](#maven_assembly_plugin)
  - [Debug a dockerized Java application](#debug_dockerized_java_app) 
- [Resources](#resources) 

* * * 

<h2 id="context">Context</h2>  

In case you're using Docker Compose for running several containers on a machine, sooner or later you'll end-up in a situation where you'll need to ensure service A runs *before* service B. The classic example is an application which needs to access a database; if both of these compose services are started via the *docker-compose up* command, there is a chance this will fail, since the application service might start before the database service and it will not find a database able to handle its SQL statements.
The guys behind Docker Compose have thought about this issue and provided the __[depends_on](https://docs.docker.com/compose/compose-file/#depends_on)__ directive for expressing dependency between services.  

On the other hand, just because the database service was started before application service, it doesn't mean that the database is ready to handle incoming connections (the *ready* state). Any relational database system needs to start its own services before being able to handle incoming connections (for instance, check a simplified view over [SQL Server startup steps](https://sqltimes.wordpress.com/2013/02/10/sql-server-start-up-steps/)) and the startup might take a while, so we need a better mechanism of detecting the *ready* state of a particular compose service, in addition to specifying its dependents.  

In this post I will present several approaches inspired by the official [recommendations](https://docs.docker.com/compose/startup-order/) and other sources.
Each approach will use its own compose file and each of these compose files contains at least 2 services: a Java 8 console application and a MySQL v5.7 database; the former will connect to the latter using [plain-old JDBC](https://docs.oracle.com/javase/tutorial/jdbc/basics/connecting.html), will read some [metadata](https://en.wikipedia.org/wiki/Information_schema) and then will print them to the console.  
All compose files will use the same Java application [Docker image](https://github.com/satrapu/jdbc-with-docker/blob/master/Dockerfile-jdbc-with-docker-console-runner).  

There is also a bonus section at the [end](#bonus) of this post, so please check it out too!

__IMPORTANT THINGS__
* My environment
  *  Windows 10 x64 Pro
  *  Docker v18.03.1-ce-win65 (17513)
  *  Docker Compose v1.21.1, build 7641a569
*  The source code used by this post can be found on [GitHub](https://github.com/satrapu/jdbc-with-docker)
* All commands below must be executed from a Powershell console run as admin
* Also, since I'm lazy, I have embedded Linux shell commands inside the Docker Compose files, which is most definately not a best practice, but since the point of this post is service startup order and not Docker Compose file best practices, please endure
* I'm using "mvn", "[docker-compose down](https://docs.docker.com/compose/reference/down/)" and "[docker-compose build](https://docs.docker.com/compose/reference/build/)" commands before starting any compose service via "[docker-compose up](https://docs.docker.com/compose/reference/up/)" to ensure:
  *  I will run the lastest build of the Java application using [default](http://www.adam-bien.com/roller/abien/entry/configuring_default_goal_in_maven) Maven goal; in my case this is: *clean compile assembly:single*
  *  Any running compose service will be stopped
  *  Any Docker image declared in the compose file will be rebuilt
* The aforementioned compose files make use of variables declared in a [.env](https://docs.docker.com/compose/env-file/) file, with the following content:

````ini
mysql_root_password=<ENTER_A_PASSWORD_HERE>

mysql_database_name=jdbcwithdocker
mysql_database_user=satrapu
mysql_database_password=<ENTER_A_DIFFERENT_PASSWORD_HERE>

java_jvm_flags=-Xmx512m
java_debug_port=9876

# Use "suspend=y" to ensure the JVM will pause the application, 
# waiting for a debugger to be attached
java_debug_settings=-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=y,address=9876

# The amount of time between two consecutive health state checks 
# (used by docker-compose-using-healthcheck.yml)
healthcheck_interval=2s

# The maximum amount of time each healthcheck state try must end in
# (used inside docker-compose-using-healthcheck.yml)
healthcheck_timeout=5s

# The maximum amount of retries before giving up and considering 
# the Docker container in an unhealthy state
# (used by docker-compose-using-port-checking.yml and docker-compose-using-api.yml)
healthcheck_retries=20

# The amount of time between two consecutive queries against the database
# (used by docker-compose-using-port-checking.yml)
check_db_connectivity_interval=2s

# The maximum amount of retries before giving up and considering 
# the database is not able to process incoming connections
# (used by docker-compose-using-port-checking.yml)
check_db_connectivity_retries=20

# The Docker API version to use when querying for container metadata
# (used by docker-compose-using-api.yml)
docker_api_version=1.37
````

Since the .env file contains sensitive things like database passwords, it should not be put under source control.  

<h2 id="service_healthy">Solution #1: Use depends_on, condition and service_healthy</h2>  
This solution uses this Docker compose file: __[docker-compose-using-healthcheck.yml](https://github.com/satrapu/jdbc-with-docker/blob/master/docker-compose-using-healthcheck.yml)__.  
Run it using the following commands:
````powershell
mvn `
;docker-compose --file docker-compose-using-healthcheck.yml down --rmi local `
;docker-compose --file docker-compose-using-healthcheck.yml build `
;docker-compose --file docker-compose-using-healthcheck.yml up
```` 

Starting with version [1.12](https://docs.docker.com/release-notes/docker-engine/#1120-2016-07-28), Docker has added the [HEALTHCHECK](https://docs.docker.com/engine/reference/builder/#healthcheck) Dockerfile instruction used for verifying whether a container is still working; Docker Compose file has added support for using the health check when expressing a service dependency since version 2.1, as documented inside the [compatibility matrix](https://docs.docker.com/compose/compose-file/compose-versioning/#compatibility-matrix).  

My database service will define its [health check](https://docs.docker.com/compose/compose-file/compose-file-v2/#healthcheck) as a My SQL client command which will periodically query whether the underlying MySQL database is ready to handle incoming connections via the [USE](https://dev.mysql.com/doc/refman/5.7/en/use.html) SQL statement:
````yml
...
db:
    image: mysql:5.7.20
    healthcheck:
      test: >
        mysql \
          --host='localhost' \
          --user='${mysql_database_user}' \
          --password='${mysql_database_password}' \
          --execute='USE ${mysql_database_name}' \
      interval: ${healthcheck_interval}
      timeout: ${healthcheck_timeout}
      retries: ${healthcheck_retries}
...
````

Keep in mind USE statement is not the only way of performing such check. For instance, one could periodically run a SQL script which would test whether the database is accessible *and* that the database user has been granted all the expected permissions (e.g. can perform INSERT against a particular table, etc.).  

My application service will be [started](https://docs.docker.com/compose/compose-file/compose-file-v2/#depends_on) as soon as the database service has reached the "healthy" state:
````yml
...
app:
    image: satrapu/jdbc-with-docker-console-runner
    ...
    depends_on:
      db:
        condition: service_healthy
...
````

As you can see, stating the dependency between db and app services is pretty easy, same as doing a health check. Even better, these things are built-in Docker Compose.  

And now the __bad__ news: since Docker Compose file format is used by Docker Swarm too, the development team has decided to mark this feature as obsolete starting with compose file v3, as documented [here](https://docs.docker.com/compose/compose-file/#depends_on); see more reasoning behind this decision [here](https://github.com/docker/compose/issues/4305#issuecomment-276527457).  
The depends_on, condition and service_healthy are usable only when using older compose file versions (v2.1 up to and including v2.4).  
Keep in mind Docker Compose might remove support for these versions in a future release, but as long as you're OK with using compose file versions before v3, this solution is very simple to understand and use.

<h2 id="port-checking">Solution #2: Port checking with a twist</h2>
This solution uses this Docker compose file: __[docker-compose-using-port-checking.yml](https://github.com/satrapu/jdbc-with-docker/blob/master/docker-compose-using-port-checking.yml)__.  
Run it using the following commands:
````powershell
mvn `
;docker-compose --file docker-compose-using-port-checking.yml down --rmi local  `
;docker-compose --file docker-compose-using-port-checking.yml build `
;docker-compose --file docker-compose-using-port-checking.yml up --exit-code-from check_db_connectivity check_db_connectivity `
;if ($LASTEXITCODE -eq 0) { docker-compose --file docker-compose-using-port-checking.yml up app } `
else { echo "ERROR: Failed to start service due to one of its dependencies!" }
```` 

This solution was inspired by [one](https://8thlight.com/blog/dariusz-pasciak/2016/10/17/docker-compose-wait-for-dependencies.html) of Dariusz Pasciak's articles, but I'm not just checking whether MySQL port 3306 is open (*port checking*), as Dariusz is doing: I'm running the aforementioned USE SQL statement using a MySQL client found inside the __check_db_connectivity__ compose service to ensure the underlying database can handle incoming connections (*the twist*); additionally, the exit code of the check_db_connectivity service will be evaluated due to the *--exit-code-from check_db_connectivity* compose option and if different than 0 (which marks the db service is in desired ready state), an error message will be printed and app service will not start.

* Docker Compose will try starting check_db_connectivity service, but it will see that it has a dependency on db service:
 
  ````yml
  ...
   db:
      image: mysql:5.7.20
  ...
   check_db_connectivity:
      image: activatedgeek/mysql-client:0.1
      depends_on:
        - db
  ...
  ````
* Docker Compose will start db service
* Docker Compose will then start check_db_connectivity service, which will initiate a loop checking that the MySQL database can handle incoming connections
* Docker Compose will wait for check_db_connectivity service to finish its loop, as the loop is part of the service [entry point](https://docs.docker.com/compose/compose-file/#entrypoint):
  ````yml
  check_db_connectivity:
    image: activatedgeek/mysql-client:0.1
    entrypoint: >
      /bin/sh -c "
        sleepingTime='${check_db_connectivity_interval}'
        totalAttempts=${check_db_connectivity_retries}
        currentAttempt=1

        echo \"Start checking whether MySQL database \"${mysql_database_name}\" is up & running\" \
              \"(able to process incoming connections) each $$sleepingTime for a total amount of $$totalAttempts times\"

        while [ $$currentAttempt -le $$totalAttempts ]; do
          sleep $$sleepingTime
          
          mysql \
            --host='db' \
            --port='3306' \
            --user='${mysql_database_user}' \
            --password='${mysql_database_password}' \
            --execute='USE ${mysql_database_name}'

          if [ $$? -eq 0 ]; then
            echo \"OK: [$$currentAttempt/$$totalAttempts] MySQL database \"${mysql_database_name}\" is up & running.\"
            return 0
          else
            echo \"WARN: [$$currentAttempt/$$totalAttempts] MySQL database \"${mysql_database_name}\" is still NOT up & running ...\"
            currentAttempt=`expr $$currentAttempt + 1`
          fi
        done;

        echo 'ERROR: Could not connect to MySQL database \"${mysql_database_name}\" in due time.'
        return 1"
  ````
* Docker Compose will then start app service; by the time this service is running, the MySQL database is able to handle incoming connections
  ````yml
    app:
      image: satrapu/jdbc-with-docker-console-runner
      depends_on:
        - db
  ````

This solution is similar with the [previous one](#service_healthy) in the sense that the application service waits till the database service enters a specific state, but then without using a Docker Compose obsolete feature.

<h2 id="docker_engine_api">Solution #3: Invoke Docker Engine API</h2>
This solution uses this Docker compose file: __[docker-compose-using-api.yml](https://github.com/satrapu/jdbc-with-docker/blob/master/docker-compose-using-api.yml)__.  
Run it using the following commands:
````powershell
$Env:COMPOSE_CONVERT_WINDOWS_PATHS=1 `
;mvn `
;docker-compose --file docker-compose-using-api.yml down --rmi local  `
;docker-compose --file docker-compose-using-api.yml build `
;docker-compose --file docker-compose-using-api.yml up
````  

__IMPORTANT__  
Running the above commands without including __COMPOSE_CONVERT_WINDOWS_PATHS__ environment variable will fail:  
````powershell
...
Creating jdbc-with-docker_app_1 ... error

ERROR: for jdbc-with-docker_app_1  Cannot create container for service app: b'Mount denied:\nThe source path "\\\\var\\\\run\\\\docker.sock:/var/run/docker.sock"\nis not a valid Windows path'
...
````
This issue and its fix are documented [here](https://github.com/docker/for-win/issues/1829#issuecomment-376328022).

I really like the idea of expressing dependencies between compose services via health checks.  
Since *condition* form of *depends_on* will be gone sooner or later, I thought about implementing something conceptually similar and one way is using [Docker Engine API](https://docs.docker.com/develop/sdk/).  

My approach is to periodically query the health state of the database service from within the application service entry point by making an HTTP request to the Docker API endpoint and parse the response using [jq](https://stedolan.github.io/jq/), a command-line JSON processor; the Java application will start as soon as the database service has reached the "healthy" state.  

First, I will get the JSON document containing information about all running containers via a simple [curl](https://curl.haxx.se/docs/manpage.html) command. The special thing is to use the [unix-socket](https://curl.haxx.se/docs/manpage.html#--unix-socket) curl option, since this kind of socket is used by Docker daemon.  
Additionally, I need to expose the [docker.sock](https://docs.docker.com/engine/reference/commandline/dockerd/#examples) as a volume to the container running curl command to allow it communicate with the local Docker daemon.

__IMPORTANT__  
Sharing your local Docker daemon socket should be done with care, as it *can* lead to security issues, as very clearly presented [here](https://www.ctl.io/developers/blog/post/tutorial-understanding-the-security-risks-of-running-docker-containers), so carefully consider all things *before* using this approach!  

Now that the security ad has been played, below you may find an example of what the stand-alone command used for listing all Docker containers running on the local host would look like - please note I'm running curl from within a Docker container, [byrnedo/alpine-curl](https://hub.docker.com/r/byrnedo/alpine-curl/), while the actual command is executed from a container based on [openjdk:8-jre-alpine](https://hub.docker.com/_/openjdk/) Docker image:
````powershell
# Ensure db service is running before querying its metadata
docker-compose --file docker-compose-using-api.yml up -d db `
;docker container run `
       --rm `
       -v /var/run/docker.sock:/var/run/docker.sock `
       byrnedo/alpine-curl `
          --silent `
          --unix-socket /var/run/docker.sock `
          http://v1.37/containers/json
 ````
 The output would look similar to this:
 ````json
 [
   ...
  [  
   {  
      "Id":"5d9108769de3641692a5d636aa361866f09e6403309e6262520447dae9115344",
      "Names":[  
         "/jdbc-with-docker_db_1"
      ],
      "Image":"mysql:5.7.20",
      "ImageID":"sha256:7d83a47ab2d2d0f803aa230fdac1c4e53d251bfafe9b7265a3777bcc95163755",
      "Command":"docker-entrypoint.sh mysqld",
      "Created":1525887950,
      "Ports":[  
         {  
            "IP":"0.0.0.0",
            "PrivatePort":3306,
            "PublicPort":32771,
            "Type":"tcp"
         }
      ],
      "Labels":{  
         "com.docker.compose.config-hash":"cea84824338bc0ea6a7da437084f00a8bfc9647b91dd8de5e41694269498dec6",
         "com.docker.compose.container-number":"1",
         "com.docker.compose.oneoff":"False",
         "com.docker.compose.project":"jdbc-with-docker",
         "com.docker.compose.service":"db",
         "com.docker.compose.version":"1.21.1"
      },
      "State":"running",
      "Status":"Up 6 seconds (healthy)",
      "HostConfig":{  
         "NetworkMode":"jdbc-with-docker_default"
      },
      "NetworkSettings":{  
         "Networks":{  
            "jdbc-with-docker_default":{  
               "IPAMConfig":null,
               "Links":null,
               "Aliases":null,
               "NetworkID":"fd1c60a463a8b39dd3cb9b34c8e5792c069e18cd5076f6321f5554c10ec1765d",
               "EndpointID":"b80cfc9c45e0816cd9af9507f76e3a0f9f1e203d2d2b0e081b8affc1293e8cf4",
               "Gateway":"172.18.0.1",
               "IPAddress":"172.18.0.2",
               "IPPrefixLen":16,
               "IPv6Gateway":"",
               "GlobalIPv6Address":"",
               "GlobalIPv6PrefixLen":0,
               "MacAddress":"02:42:ac:12:00:02",
               "DriverOpts":null
            }
         }
      },
      "Mounts":[  
         {  
            "Type":"volume",
            "Name":"jdbc-with-docker_jdbc-with-docker-mysql-data",
            "Source":"/var/lib/docker/volumes/jdbc-with-docker_jdbc-with-docker-mysql-data/_data",
            "Destination":"/var/lib/mysql",
            "Driver":"local",
            "Mode":"rw",
            "RW":true,
            "Propagation":""
         }
      ]
   },
   ...
]
````  

Secondly, I will extract the health state of the database service using [various](https://stedolan.github.io/jq/manual/#Builtinoperatorsandfunctions) jq operators and functions: 
````bash
jq '.[] | select(.Names[] | contains("_db_")) | select(.State == "running") | .Status | contains("healthy")'

# The output should be "true" in case the db service has reached the healthy state
````
* __.[]__ : this will select all records from the given JSON document
* __select(.Names[] \| contains("\_db\_"))__ : this will select the records whose "Names" array property has a record containing the "\_db\_" string - the name of a Docker container created by Docker Compose contains the service name; in our case it is "db"
* __select(.State == "running")__ : this will select only running Docker containers
* __.Status \| contains("healthy")__ : this will select the value of the "Status" property, which, in case the container has reached healthy state, should be "true"  

In order to reach the final jq command found inside the Docker Compose file, I have experimented using [jq Playground](https://jqplay.org/s/svMcFCRZ31).  
Please note this is not the only way of extracting the health status out of the Docker JSON - use your imagination to come up with better jq commands.

<h2 id="conclusion">Conclusion</h2>  

Controlling service startup order in Docker Compose is something we cannot ignore, but I hope the approaches presented in this post will help anybody understand where to start from.  
I'm fully aware these are not the *only* options - for instance, [ContainerPilot](https://www.joyent.com/containerpilot), which implement the [autopilot pattern](http://autopilotpattern.io/), looks very interesting. Another option is moving the delayed startup logic inside the dependent service (e.g. have my Java console application use a connection pool with a longer timeout used for fetching connections to MySQL database), but this requires glue code for checking each dependency (one approach for MySQL, another one for a cache provider, like Memcache, etc.).  
The good news is that there are many options, you just need to identify which one is more/most suitable for your use case.

<h2 id="bonus">Bonus</h2>  

While working on the Java console application, I have encountered several challenges and I thought I should also mention them here, along with their solutions, as this may help others too.

<h3 id="maven_assembly_plugin">Maven Assembly plugin</h3>  

Adding a dependency in a Maven pom.xml file is ~~trivial~~[well documented](https://maven.apache.org/guides/introduction/introduction-to-dependency-mechanism.html#Importing_Dependencies), but then you need to ensure that the dependency JAR file(s) will be correctly packaged with your console application.  
One way of packing all files in one JAR is using [Maven Assembly plugin](http://maven.apache.org/plugins/maven-assembly-plugin/) and use its [assembly:single](http://maven.apache.org/plugins/maven-assembly-plugin/single-mojo.html) goal, like I [did](https://github.com/satrapu/jdbc-with-docker/blob/master/pom.xml#L31).  
Running this goal will create an *jdbc-with-docker-jar-with-dependencies.jar* file under the *./target* folder instead if the usual *jdbc-with-docker.jar*, that's why I'm [renaming](https://github.com/satrapu/jdbc-with-docker/blob/master/Dockerfile-jdbc-with-docker-console-runner#L5) the JAR file inside the Dockerfile to a shorter name.

<h3 id="debug_dockerized_java_app">Debug dockerized Java application</h3>  

Debugging a Java process means launching the process with several debugging related [parameters](https://docs.oracle.com/javase/8/docs/technotes/guides/jpda/conninv.html#Invocation).  
Two of these parameters are crucial for debugging:
* *address*, representing the port where the JVM listens for a debugger; the same port must be configured on IDE side when starting the debug session
* *suspend*, which specifies whether the JVM should block and wait until a debugger is attached

Since I'm using Visual Studio Code for developing this particular Java application, I need to create a debug configuration and set the port which is specified inside the .env file via key *java_debug_port* (e.g. java_debug_port=9876).  
On the other hand, since the application will run inside a container, this port needs to be published to the Docker host where the IDE is running on.   

Launch the application and see the JVM waiting for a debugger:
````powershell
λ  $Env:COMPOSE_CONVERT_WINDOWS_PATHS=1 `
>> ;mvn `
>> ;docker-compose --file docker-compose-using-api.yml down --rmi local  `
>> ;docker-compose --file docker-compose-using-api.yml build `
>> ;docker-compose --file docker-compose-using-api.yml up
# ...
# Creating jdbc-with-docker_db_1 ... done
# Creating jdbc-with-docker_app_1 ... done
# Attaching to jdbc-with-docker_db_1, jdbc-with-docker_app_1
# ...
# db_1   | 2018-05-12T20:46:19.560436Z 0 [Note] Beginning of list of non-natively partitioned tables
# db_1   | 2018-05-12T20:46:19.574074Z 0 [Note] End of list of non-natively partitioned tables
# app_1  | Start checking whether MySQL database jdbcwithdocker is up & running (able to process incoming connections) each 2s for a total amount of 20 times
# app_1  | OK: [1/20] MySQL database jdbcwithdocker is up & running.
# app_1  | Listening for transport dt_socket at address: 9876
````  

Docker Compose can get the host port via the following command:
````powershell
  docker-compose --file docker-compose-using-api.yml  port --protocol=tcp app 9876
  # 0.0.0.0:32809
````

Visual Studio Code needs to have its debug configuration use port *32809*:
````json
{
    // Use IntelliSense to learn about possible attributes.
    // Hover to view descriptions of existing attributes.
    // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
    "version": "0.2.0",
    "configurations": [
        {
            "type": "java",
            "name": "Debug (Attach)",
            "request": "attach",
            "hostName": "localhost",
            "port": 32809
        }
    ]
}
````  

Then launch the debug configuration and see the following output generated by the Java application:
````powershell
...
app_1  | JDBC_URL="jdbc:mysql://address=(protocol=tcp)(host=db)(port=3306)/jdbcwithdocker?useSSL=false"
app_1  |
app_1  | JDBC_USER="satrapu"
app_1  |
app_1  | JDBC_PASSWORD="********"
app_1  |
app_1  | --------------------------------------------------------------------------------------------------------------
app_1  | |              TABLE_SCHEMA |                                         TABLE_NAME |                TABLE_TYPE |
app_1  | --------------------------------------------------------------------------------------------------------------
app_1  | |        information_schema |                                     CHARACTER_SETS |               SYSTEM VIEW |
app_1  | |        information_schema |                                         COLLATIONS |               SYSTEM VIEW |
app_1  | |        information_schema |              COLLATION_CHARACTER_SET_APPLICABILITY |               SYSTEM VIEW |
...
app_1  | |        information_schema |                                              VIEWS |               SYSTEM VIEW |
app_1  | --------------------------------------------------------------------------------------------------------------
app_1  | Application was successfully able to fetch data out of the underlying database!
jdbc-with-docker_app_1 exited with code 0
````  

<h2 id="resources">Resources</h2>  

* [Docker Compose](https://github.com/docker/compose/)  
* [Docker Compose command-line reference](https://docs.docker.com/compose/reference/)
* [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
* [Docker Engine API v1.37](https://docs.docker.com/engine/api/v1.37/)
* [jq](https://stedolan.github.io/jq/)
* [jq Manual](https://stedolan.github.io/jq/manual/)
* [jq Playground](https://jqplay.org/)
* [JDBC - The Java Tutorials](https://docs.oracle.com/javase/tutorial/jdbc/TOC.html)
* [Debugging Java in VS Code](https://code.visualstudio.com/docs/languages/java#_debugging)