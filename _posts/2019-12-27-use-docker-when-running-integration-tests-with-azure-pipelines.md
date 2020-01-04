---
layout: post
title: "Use Docker when running integration tests with Azure Pipelines"
date: 2019-12-27 18:08:39 +0200
tags: [programming, dotnet, dotnet-core, aspnet-core, azure-devops, azure-pipeline, integration-tests, docker, postgresql, linux-containers, windows-containers]
---

- [Context](#context)
- [Provide a database for Azure Pipelines](#db-for-azure-pipelines)
- [Setup EF Core provider](#setup-ef-core-provider)
- [Use Docker in Azure Pipelines](#docker-in-azure-pipelines)
  - [Service containers](#service-containers)
    - [Declare Docker containers](#declare-containers)
    - [Map a service to a Docker container](#mapping-a-service)
    - [Use Docker container published port](#using-container-port)
  - [Use self-managed Docker containers](#self-managed-docker-containers)
    - [Install and run Docker on macOS](#run-docker-on-macos)
    - [Run dockerized database](#run-dockerized-database)
    - [Check database ready-state](#check-database-ready-state)
      - [Check database ready-state using log-polling](#check-database-ready-state-using-log-polling)
      - [Check database ready-state using Docker healthcheck](#check-database-ready-state-using-healthcheck)
    - [Identify database port](#identify-database-port)
    - [Update database connection string](#update-database-connection-string)
  - [Service containers vs. self-managed containers](#comparison)
- [Run integration tests](#run-integration-tests)
- [Other challenges](#other-challenges)
  - [Run PostgreSQL database locally using Docker](#run-postgresql-locally-using-docker)
  - [Fix publishing test results](#publish-test-results)
  - [Publish test results raw files as pipeline artifacts](#publish-raw-test-results-as-artifacts)
- [Next steps](#next-steps)
- [Conclusion](#conclusion)

* * *

<!-- markdownlint-disable MD033 -->
<h2 id="context">Context</h2>
<!-- markdownlint-disable MD033 -->

In my previous Azure DevOps related [article](https://crossprogramming.com/2019/03/17/build-asp-net-core-app-using-azure-pipelines.html#run-automated-tests) I was saying that since I'm using the in-memory EF Core [provider](https://docs.microsoft.com/en-us/ef/core/providers/in-memory/), my integration tests were kind of lame, as they were not targeting a real database. On the other hand, this was the perfect opportunity for me to dive deeper into the capabilities of Azure Pipelines and discover a solution for this problem. Thus, the purpose of this post is to present several approaches for provisioning a relational database using Docker when running integration tests with Azure Pipelines.

<!-- markdownlint-disable MD033 -->
<h2 id="db-for-azure-pipelines">Provide a database for Azure Pipelines</h2>
<!-- markdownlint-disable MD033 -->

Since Azure Pipelines is running in the cloud, one could use a database running also in the cloud (AWS, Azure, etc.); a different approach is to run the database inside a Docker container managed by the pipeline - this is the approach presented by this post.  
Choosing Docker is a good choice since both the developer and Azure Pipelines can use the same Docker image, thus ensuring the outcomes of running the integration tests on both developer machine and Azure Pipelines will be same. Another reason for using Docker is simplicity: you do not need to install a database server on your development machine, you just run a Docker container.  
On the other hand, using Docker does pose its own challenges, as I need to pick a relational database for which I can find Docker images for running Linux containers _and_ Windows containers, as the [windows-2019](https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/hosted?view=azure-devops#use-a-microsoft-hosted-agent) hosted agent I use for running builds targeting Windows OS cannot run Linux containers, only Windows ones.  
A different challenge is to find small enough Docker images so that pulling them will not (greatly) impact the build time. This particular challenge can be resolved by using [self-hosted agents](https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/agents?view=azure-devops#install), since the agent can be provisioned with the appropriate Docker images, thus eliminating the need of pulling them during the build. On the other hand, since I'm not using such agents, I need to rely on the classic image pulling approach and thus experiencing the longer build times.  
After doing some research, I have found the following Docker images which can be used to run both Linux and Windows containers:

| Database Server | Container Type | Docker Image*                                                                                                       | Image Size (MB)** |
| --------------- | -------------- | ------------------------------------------------------------------------------------------------------------------- | ----------------- |
| PostgreSQL      | Linux          | [postgres:12-alpine](https://hub.docker.com/_/postgres/)                                                            | 146               |
| PostgreSQL      | Windows        | [stellirin/postgres-windows:12](https://hub.docker.com/r/stellirin/postgres-windows)                                | 452               |
| SQL Server      | Linux          | [mcr.microsoft.com/mssql/server:2017-latest-ubuntu](https://hub.docker.com/_/microsoft-mssql-server)***             | 1333              |
| SQL Server      | Windows        | [microsoft/mssql-server-windows-developer:1709](https://hub.docker.com/r/microsoft/mssql-server-windows-developer/) | 10800             |

\* Latest version at the time of the investigation (December 2019)  
\*\* Rounded values based on the output of the `docker image` command  
\*\*\* I could not find any SQL Server 2019 Docker image for Windows, so I had to stick with SQL Server 2017

SQL Server Docker images are *very* large when compared to PostgreSQL ones, especially the Windows ones. Considering this aspect and since the purpose of this post is more generic and not dependant on a particular database server, I have decided to use PostgreSQL Docker images for running a database to be targeted by the integration tests.

<!-- markdownlint-disable MD033 -->
<h2 id="setup-ef-core-provider">Setup EF Core provider</h2>
<!-- markdownlint-disable MD033 -->

Since I have chosen PostgreSQL as my database server, I have picked [Npgsql](http://www.npgsql.org/efcore/) as my EF Core provider because it's on the [official provider list](https://docs.microsoft.com/en-us/ef/core/providers/) and it's free.  
This provider was specified inside my [Startup class](https://github.com/satrapu/aspnet-core-logging/blob/cb97b1604549b1519b31cfa6f42c33d545564924/Sources/Todo.WebApi/Startup.cs#L48) as:

```cs
...
public void ConfigureServices(IServiceCollection services)
{
    // Other services

    services.AddDbContext<TodoDbContext>((serviceProvider, dbContextOptionsBuilder) =>
    {
        var connectionString = Configuration.GetConnectionString("Todo");
        dbContextOptionsBuilder.UseNpgsql(connectionString)
                               .EnableSensitiveDataLogging()
                               .UseLoggerFactory(serviceProvider.GetRequiredService<ILoggerFactory>());
    });

    // Other services
}
...
```

As a side note, the [EnableSensitiveDataLogging](https://docs.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.dbcontextoptionsbuilder.enablesensitivedatalogging?view=efcore-2.2) method should be use with care as logging SQL statements with their actual parameter values may leak passwords or any other sensitive data - see more inside the aforementioned documentation.  
The application expects to find a [connection string](https://www.connectionstrings.com/npgsql/) named __Todo__ pointing to a PostgreSQL database inside its configuration. This means the developer might choose to add a connection string inside the [appsettings.json](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/configuration/?view=aspnetcore-2.2#default-configuration) file, like this:

```json
{
  // Other sections

  "ConnectionStrings": {
    "Todo": "Server=127.0.0.1;Port=5432;Database=aspnet-core-logging-dev;Username=...;Password=...;"
  },

  // Other section
}
```

This is the easy way, but storing credentials in a file put under source control is __not__ a good idea as you will leak sensitive data, so my appsettings.json file looks like this:

```json
{
  // Other sections

  "ConnectionStrings": {
    "Todo": "<DO_NOT_STORE_SENSITIVE_DATA_HERE>"
  },

  // Other section
}
```

In order to run the application and integration tests on my local machine, I have defined an environment variable storing the connection string which points to a PostgreSQL database running in a local Docker container (Linux container):

```powershell
# Display the contents of the "ConnectionStrings__Todo"
# environment variable via a PowerShell command.
# The user name and password below have been intentionally replaced with dots.
Get-ChildItem Env:ConnectionStrings__Todo

Name                           Value
----                           -----
ConnectionStrings__Todo        Host=localhost;Port=5432;Database=aspnet-core-logging-dev;Username=...;Password=...;
```

The Azure Pipelines task used for running the integration tests will use a similar approach for providing the connection string, thus avoiding leaking sensitive data.  
When running the application in production, one might store the connection string (and other sensitive data) using [Key Vault](https://docs.microsoft.com/en-us/aspnet/core/security/key-vault-configuration?view=aspnetcore-2.2), [Data Protection](https://docs.microsoft.com/en-us/aspnet/core/security/data-protection/introduction?view=aspnetcore-2.2) or something else which meets the application security needs.

<!-- markdownlint-disable MD033 -->
<h2 id="docker-in-azure-pipelines">Use Docker in Azure Pipelines</h2>
<!-- markdownlint-disable MD033 -->

The good news is that Azure Pipelines offer support for running Docker containers out-of-the-box via  [service containers](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/service-containers?view=azure-devops&tabs=yaml), the bad news is that they do not work on agents running macOS, only on those running Linux or Windows.  
Since my aim is to run integration tests on all 3 operating systems, I had to find a different approach - and I did, as seen [below](#self-managed-docker-containers); on the other hand, I have documented the official one too.

<!-- markdownlint-disable MD033 -->
<h3 id="service-containers">Service containers</h3>
<!-- markdownlint-disable MD033 -->

> A service container enables you to automatically create, network, and manage the lifecycle of your containerized service.

I believe the quote above taken from official documentation [page](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/service-containers?view=azure-devops&tabs=yaml) is pretty clear: Azure Pipelines will manage the containers, you just have to declare them inside the pipeline YAML file in a [resources](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=schema#container-resource) section, then one or more jobs will declare a [service](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/service-containers?view=azure-devops&tabs=yaml#single-container-job) mapped to this container.  

__IMPORTANT__: The source code used by this approach can be found inside the [feature/use-service-containers](https://github.com/satrapu/aspnet-core-logging/tree/feature/use-service-containers) branch.

<h4 id="declare-containers">Declare Docker containers</h4>
The YAML file representing the pipeline needs to declare 2 containers, each one pointing to a Docker image targeting a particular operating system, Linux and Windows, as explained inside the table [above](#db-for-azure-pipelines).  

Declaring the containers with their images, ports et al. is done like this:

```yaml
# Fragment found in "azure-pipelines.yml" file
...
resources:
  containers:
  - container: 'postgres_linux_container_for_integration_tests'
    image: 'postgres:11.3-alpine'
    ports:
    - 9999:5432/tcp
    env:
      POSTGRES_DB: $(IntegrationTests.Database.Todo.Name)
      POSTGRES_USER: $(IntegrationTests.Database.Todo.Username)
      POSTGRES_PASSWORD: $(IntegrationTests.Database.Todo.Password)
  - container: 'postgres_windows_container_for_integration_tests'
    image: 'stellirin/postgres-windows:11.3'
    ports:
    - 5432/tcp
    env:
      POSTGRES_DB: $(IntegrationTests.Database.Todo.Name)
      POSTGRES_USER: $(IntegrationTests.Database.Todo.Username)
      POSTGRES_PASSWORD: $(IntegrationTests.Database.Todo.Password)
```

Please notice the 2 different ways PostgreSQL port is being exposed to the Docker host - see [this section](#using-container-port) for the full explanation.  
The environment variables accompanying the containers point to variables declared inside the [variables](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/variables?view=azure-devops&tabs=yaml) section from the pipeline file, as seen [here](https://github.com/satrapu/aspnet-core-logging/blob/232a3d12fe71f427221f0d2f602d41c4bd93ac2b/Build/azure-pipelines.yml#L108).

This is how the [template jobs](https://crossprogramming.com/2019/03/17/build-asp-net-core-app-using-azure-pipelines.html#use-templates) know about the Docker ports:
{% raw %}

```yaml
# Fragment found in "azure-pipelines.yml" file
...
jobs:
- template: './azure-pipelines.job-template.yml'
  parameters:
    job:
      name: 'linux'
      displayName: 'Build on Linux'
    pool:
      # Need a VM capable of running Linux containers
      vmImage: 'ubuntu-16.04'
    services:
      db4it:
        containerName: 'postgres_linux_container_for_integration_tests'
        databaseConnectionString: >-
          Host=localhost;
          Port=9999;
          Database=$(IntegrationTests.Database.Todo.Name);
          Username=$(IntegrationTests.Database.Todo.Username);
          Password=$(IntegrationTests.Database.Todo.Password);
    ...
- template: './azure-pipelines.job-template.yml'
  parameters:
    job:
      name: 'windows'
      displayName: 'Build on Windows'
    pool:
      # Need a VM capable of running Windows containers
      vmImage: 'windows-2019'
    services:
      db4it:
        containerName: 'postgres_windows_container_for_integration_tests'
        databaseConnectionString: >-
          Host=localhost;
          Port=$(Agent.Services.db4it.Ports.5432);
          Database=$(IntegrationTests.Database.Todo.Name);
          Username=$(IntegrationTests.Database.Todo.Username);
          Password=$(IntegrationTests.Database.Todo.Password);
  ...
...
```

{% endraw %}
The connection string stored inside **databaseConnectionString** job parameter follows [Npgsql format](https://www.npgsql.org/doc/connection-string-parameters.html).  
The database host is set to __localhost__ since each build agent will start its own Docker container running a PostgreSQL database.  
Once again, please notice the 2 different ways database port is being referenced - see [this section](#using-container-port) for the full explanation.

<h4 id="mapping-a-service">Map a service to a Docker container</h4>
The template job will make use of a service named __db4it__ which is mapped to one of the previously defined containers:
{% raw %}

```yaml
# Fragment found in "azure-pipelines.job-template" file
parameters:
  job:
    name: ''
    displayName: ''
  pool: ''
  services:
    db4it:
      containerName: ''
      databaseConnectionString: ''
  build:
    configuration: 'Release'
  ...
jobs:
- job: ${{ parameters.job.name }}
  displayName: ${{ parameters.job.displayName }}
  continueOnError: False
  pool: ${{ parameters.pool }}
  workspace:
    clean: all
  services:
    # The actual service name is provided as a parameter - see the above YAML fragment
    db4it: ${{ parameters.services.db4it.containerName }}
  steps:
  ...
```

{% endraw %}

<h4 id="using-container-port">Use Docker container published port</h4>
In order for the integration tests to be able to access the containerized database, I need to [publish](https://docs.docker.com/config/containers/container-networking/#published-ports) the database port __5432__ from within the Docker container to the Docker host (the virtual machine on which the job is being executed). Of course, you can publish more than one port per container.  
Publishing a port can be done in one of the following ways:

- Bind container port to a __static host port__ (as done [above](#declare-containers) when declaring the Linux container)
  - Pros
    - Very easy to configure
    - Very easy to refer to this port from within a pipeline job
  - Cons
    - Possible conflicts, as the port may already been used by a different process running on the host (e.g. a different containerized PostgreSQL database whose port 5432 has already been published)
  - Usage: You bind the container port (e.g. 5432) to a static host port (e.g. 9999) and use the host port anywhere you need to interact with the service container
- Bind container port to a __dynamic host port__ (as done [above](#declare-containers) when declaring the Windows container)
  - Pros
    - Very easy to configure
    - No more conflicts, as Docker server will automatically pick an available host port
  - Cons
    - Not so easy to refer to this port from within a pipeline job
  - Usage: You bind the container port (e.g. 5432) to a dynamic host port and use a [special way](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/service-containers?view=azure-devops&tabs=yaml#ports) of referencing the host port anywhere you need to interact with the service container
    - Example #1: Based on the aforementioned naming convention, since my service container is named __db4it__ and the container port is __5432__, the build variable pointing to the dynamic host port will be named: __Agent.Services.db4it.Ports.5432__
    - Example #2: Assuming I declared a SQL Server based service container named __mssqldb4it__ and since the default port for this containerized database is __1433__, the build variable would be named: __Agent.Services.mssqldb4it.Ports.1433__

For the sake of both learning and teaching, I have used *both* approaches; on the other hand, I recommend always choosing *binding to a dynamic host port* to avoid any port conflicts.

<!-- markdownlint-disable MD033 -->
<h3 id="self-managed-docker-containers">Use self-managed Docker containers</h3>
<!-- markdownlint-disable MD033 -->

As stated [above](#docker-in-azure-pipelines), service containers work only on Linux and Windows based agents, so in order to run a Docker container on a macOS based agent, I had to find a different approach.
I remembered seeing that [Linux](https://github.com/actions/virtual-environments/blob/master/images/linux/Ubuntu1604-README.md) and [Windows](https://github.com/actions/virtual-environments/blob/master/images/win/Windows2019-Readme.md) based agents come with Docker pre-installed and that made me think: if I'll succeed in installing Docker on a macOS based agent, then I'll be able to manually pull a Docker image and run a container using some hand-crafted scripts.  

__IMPORTANT__: The source code used by this approach can be found inside the [feature/use-self-managed-docker-containers](https://github.com/satrapu/aspnet-core-logging/tree/feature/use-self-managed-docker-containers) branch.

<!-- markdownlint-disable MD033 -->
<h4 id="run-docker-on-macos">Install and run Docker on macOS</h4>
<!-- markdownlint-disable MD033 -->

Due to some license constraints, as stated inside a GitHub issue [here](https://github.com/microsoft/azure-pipelines-image-generation/issues/738#issuecomment-516481268) and [here](https://github.com/microsoft/azure-pipelines-image-generation/issues/738#issuecomment-519571491), Microsoft cannot provision macOS based agents with Docker. On the other hand, the same GitHub issue provides a [nice little script](https://github.com/microsoft/azure-pipelines-image-generation/issues/738#issuecomment-496211237) one can use to install Docker on such agents - this script has its own issues and it doesn't work each time, as I have [discovered](https://github.com/microsoft/azure-pipelines-image-generation/issues/738#issuecomment-506980416), but [this one](https://github.com/microsoft/azure-pipelines-image-generation/issues/738#issuecomment-527013065) seem to work with a higher rate of success, even though it's installing an older version of Docker, 2.0.0.3, released on January 16th 2019 (the latest version at the time of writing this post is 2.1.0.5, released on November 18th 2019).  
Since I want to install Docker only on macOS, as it is already present on Linux and Windows, I need to run the aforementioned script only in case the current agent runs macOS:

```yaml
- script: |
      chmod +x $(Build.SourcesDirectory)/Build/start-docker-on-macOS.sh
      $(Build.SourcesDirectory)/Build/start-docker-on-macOS.sh
    name: install_and_start_docker
    displayName: Install and start Docker
    condition: |
      and
      (
          succeeded()
        , eq( variables['Agent.OS'], 'Darwin')
      )
```

Please note the *eq( variables['Agent.OS'], 'Darwin')* condition used for ensuring the [start-docker-on-macOS.sh](https://github.com/satrapu/aspnet-core-logging/blob/8176a9569da56934f83e01b37648d58300198d1e/Build/start-docker-on-macOS.sh#L1) script runs on macOS only.  
This shell script uses [Homebrew](https://brew.sh/) package manager for macOS in order to download a [particular version](https://github.com/Homebrew/homebrew-cask/blob/8ce4e89d10716666743b28c5a46cd54af59a9cc2/Casks/docker.rb) of the [Docker Desktop Community Edition cask](https://formulae.brew.sh/cask/docker); after downloading the installation media file, the script will install Docker service using unattended mode, will start the service and finally will periodically poll its status to check whether it has started or not. Polling will be performed each 5 seconds for 30 times before considering that the Docker service hasn't started and thus failing this build step and the entire Azure DevOps pipeline.

<!-- markdownlint-disable MD033 -->
<h4 id="run-dockerized-database">Run dockerized database</h4>
<!-- markdownlint-disable MD033 -->

Running the database to be targeted by integration tests in a Docker container requires several steps:

- Pulling the appropriate Docker image
- Starting a Docker container based on this image
- Checking that the database is ready to accept incoming connections
- Identify the Docker host port mapped to the container port (the default PostgreSQL port 5432)
- Ensure the PostgreSQL connection string used by the integration tests knows about this host port

Once my Azure DevOps pipeline has finished running the integration tests, there's no need to remove the Docker container and its image since I'm using [Microsoft-hosted agents](https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/agents?view=azure-devops&tabs=browser#microsoft-hosted-agents) which will have their state refreshed before each build.  
In case of using [self-hosted agents](https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/agents?view=azure-devops&tabs=browser#install), I would only remove the container and not the image to ensure the next builds will not pay the price of pulling the Docker image once again; on the other hand, one could periodically run a script on these agents to remove old Docker images to ensure disk space is not being wasted.

<!-- markdownlint-disable MD033 -->
<h4 id="check-database-ready-state">Check database ready-state</h4>
<!-- markdownlint-disable MD033 -->

Docker server has no way of knowing what's inside each container it runs, so it cannot wait for the dockerized database to reach its *ready state*, meaning reaching the phase where it can handle incoming connections. If one tries to run the integration tests right after starting the dockerized database, most likely the tests will fail as they will not find any database to connect to, since the database bootstrapping process hasn't completed yet. In order to avoid this issue, one must ensure the tests will be run *after* the database has reached its ready state.  
There are several ways of achieving this goal and this post will present 2 of them: [using log-polling](#check-database-ready-state-using-log-polling) and [using Docker healthcheck](#check-database-ready-state-using-healthcheck).

<!-- markdownlint-disable MD033 -->
<h4 id="check-database-ready-state-using-log-polling">Check database ready-state using log-polling</h4>
<!-- markdownlint-disable MD033 -->

This approach means starting the dockerized database and periodically checking its logs for a particular line which is printed when the database has reached its ready state.  
To my surprise, each PostgreSQL database Docker image I used in this post uses a different log message to signal that the database has reached its ready state:

- Linux container prints `database system is ready to accept connections`
- Windows container prints `PostgreSQL init process complete; ready for start up`

Anyway, this difference doesn't pose too much of a challenge, since I'm using job templates and thus I can easily parameterize this log message when invoking the script used for log-polling.  
The [azure-pipelines.job-template.yml](https://github.com/satrapu/aspnet-core-logging/blob/65f8f8d8b81432c45197dea5dbdf0bb4711dd5dd/Build/azure-pipelines.job-template.yml#L168) file contains a build step which invokes a PowerShell script for checking container logs:

{% raw %}

```yaml
# Runs a PowerShell script to start a Docker container hosting the database
# to be targeted by the integration tests.
# Checking whether the database is ready for processing incoming queries is done
# using Docker logs command (https://docs.docker.com/engine/reference/commandline/logs/).
- task: PowerShell@2
  name: provision_db4it_docker_container_using_log_polling
  displayName: Provision db4it Docker container using log-polling
  inputs:
    targetType: 'filePath'
    filePath: '$(Build.SourcesDirectory)/Build/Provision-Docker-container-using-log-polling.ps1'
    arguments: >-
      -DockerImageName '${{ parameters.db4it.dockerImage }}'
      -DockerImageTag '${{ parameters.db4it.dockerImageTag }}'
      -ContainerName '${{ parameters.db4it.dockerContainerName }}'
      -PortMapping '${{ parameters.db4it.dockerPortMapping }}'
      -DockerHostPortBuildVariableName '${{ parameters.db4it.dockerHostPortBuildVariableName}}'
      -ContainerEnvironmentVariables '${{ parameters.db4it.dockerContainerEnvironmentVariables }}'
      -ContainerLogPatternForDatabaseReady '${{ parameters.db4it.dockerContainerLogPatternForDatabaseReady }}'
      -SleepingTimeInMillis 250
      -MaxNumberOfTries 120
    errorActionPreference: 'stop'
    failOnStderr: True
    workingDirectory: $(Build.SourcesDirectory)
  condition: |
    and
    (
        succeeded()
      , eq( '${{ parameters.db4it.databaseReadinessStrategy }}', 'log-polling')
    )
```

{% endraw %}

Please note that this build step will be run only in case the job parameter **parameters.db4it.databaseReadinessStrategy** has been set to **log-polling** value.  
The [PowerShell script](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-self-managed-docker-containers/Build/Provision-Docker-container-using-log-polling.ps1) checks container logs via [docker logs](https://docs.docker.com/engine/reference/commandline/logs/) command:

```powershell
...
$isDatabaseReady = docker logs --tail 50 $ContainerName 2>&1 | Select-String -Pattern $ContainerLogPatternForDatabaseReady -SimpleMatch -Quiet

if ($isDatabaseReady -eq $true) {
  Write-Output "`n`nDatabase running inside container ""$ContainerName"" is ready to accept incoming connections"
  ...
}
...
```

In the above PowerShell script, I check the last 50 lines of the Docker container log file to see whether they contain the expected line whose presence means that the database ready state has been reached. Of course, the script does a lot more, but these lines are the most important ones in regards to log-polling approach.

<!-- markdownlint-disable MD033 -->
<h4 id="check-database-ready-state-using-healthcheck">Check database ready-state using Docker healthcheck</h4>
<!-- markdownlint-disable MD033 -->

This approach means starting the dockerized database and periodically checking its Docker health state which relies on either [HEALTHCHECK instruction](https://docs.docker.com/engine/reference/builder/#healthcheck) added inside the [Dockerfile](https://docs.docker.com/engine/reference/builder/) used for building the database Docker image or on the [health checking command](https://docs.docker.com/engine/reference/run/#healthcheck) used when starting the Docker container. Health checks are available starting with [Docker v1.12](https://docs.docker.com/release-notes/docker-engine/#1120-2016-07-28).  
Since neither PostgreSQL [Linux Dockerfile](https://github.com/docker-library/postgres/blob/0d0485cb02e526f5a240b7740b46c35404aaf13f/12/Dockerfile), nor [Windows Dockerfile](https://github.com/stellirin/docker-postgres-windows/blob/e41cdc60ca318ec218168e5cb1c51fa33e8be8e0/Dockerfile) make use of **HEALTHCHECK** instruction, I can make use of the health check command and consider that the container has reached its healthy state based on the outcome of the PostgreSQL [pg_isready](https://www.postgresql.org/docs/12/app-pg-isready.html) function:

{% raw %}

```yaml
# Fragment taken from azure-pipelines.yml file.
# See more here: https://github.com/satrapu/aspnet-core-logging/blob/65f8f8d8b81432c45197dea5dbdf0bb4711dd5dd/Build/azure-pipelines.yml#L152.
...
- template: './azure-pipelines.job-template.yml'
  parameters:
    job:
      name: 'macOS'
      displayName: 'Run on macOS'
    pool:
      vmImage: 'macOS-10.14'
    db4it:
      dockerImage: 'postgres'
      dockerImageTag: '12-alpine'
      ...
      dockerContainerHealthcheckCommand: >-
        pg_isready
        --host=localhost
        --port=5432
        --dbname=$(IntegrationTests.Database.Todo.Name)
        --username=$(IntegrationTests.Database.Todo.Username)
        --quiet
...
```

{% endraw %}

The **pg_isready** function will check whether the PostgreSQL server running on *localhost* (the database server is running as the top-most process inside the Docker container) and using port *5432* (the default PostgreSQL port) is ready to accept incoming connections or not.  
The [azure-pipelines.job-template.yml](https://github.com/satrapu/aspnet-core-logging/blob/65f8f8d8b81432c45197dea5dbdf0bb4711dd5dd/Build/azure-pipelines.job-template.yml#L198) file contains a build step which invokes a PowerShell script for checking container health state:

{% raw %}

```yaml
# Runs a PowerShell script to start a Docker container hosting the database
# to be targeted by the integration tests.
# Checking whether the database is ready for processing incoming queries is done
# using Docker healthcheck support (https://docs.docker.com/engine/reference/run/#healthcheck).
- task: PowerShell@2
  name: provision_db4it_docker_container_using_healthcheck
  displayName: Provision db4it Docker container using healthcheck
  inputs:
    targetType: 'filePath'
    filePath: '$(Build.SourcesDirectory)/Build/Provision-Docker-container-using-healthcheck.ps1'
    arguments: >-
      -DockerImageName '${{ parameters.db4it.dockerImage }}'
      -DockerImageTag '${{ parameters.db4it.dockerImageTag }}'
      -ContainerName '${{ parameters.db4it.dockerContainerName }}'
      -PortMapping '${{ parameters.db4it.dockerPortMapping }}'
      -DockerHostPortBuildVariableName '${{ parameters.db4it.dockerHostPortBuildVariableName}}'
      -ContainerEnvironmentVariables '${{ parameters.db4it.dockerContainerEnvironmentVariables }}'
      -HealthCheckCommand '${{ parameters.db4it.dockerContainerHealthcheckCommand }}'
      -HealthCheckIntervalInMilliseconds 250
      -MaxNumberOfTries 120
    errorActionPreference: 'stop'
    failOnStderr: True
    workingDirectory: $(Build.SourcesDirectory)
  condition: |
    and
    (
        succeeded()
      , eq( '${{ parameters.db4it.databaseReadinessStrategy }}', 'healthcheck')
    )
```

{% endraw %}

Please note that this build step will be run only in case the job parameter **parameters.db4it.databaseReadinessStrategy** has been set to **healthcheck** value.  
The [PowerShell script](https://github.com/satrapu/aspnet-core-logging/blob/65f8f8d8b81432c45197dea5dbdf0bb4711dd5dd/Build/Provision-Docker-container-using-healthcheck.ps1#L55) used for running the Docker container needs to specify the aforementioned health check command when invoking `docker container run` command:

{% raw %}

```powershell
...
Write-Output "Starting Docker container '$ContainerName' ..."
Invoke-Expression -Command "docker container run --name $ContainerName --health-cmd '$HealthCheckCommand' --health-interval ${healthCheckIntervalInSeconds}s --detach --publish ${PortMapping} $ContainerEnvironmentVariables ${DockerImageName}:${DockerImageTag}" 1>$null
Write-Output "Docker container '$ContainerName' has been started"
...
```

{% endraw %}

Checking the container health state is done via [docker inspect](https://docs.docker.com/engine/reference/commandline/inspect/) command:

{% raw %}

```powershell
...
$isDatabaseReady = docker inspect $ContainerName --format "{{.State.Health.Status}}" | Select-String -Pattern 'healthy' -SimpleMatch -Quiet

if ($isDatabaseReady -eq $true) {
    Write-Output "`n`nDatabase running inside container ""$ContainerName"" is ready to accept incoming connections"
    ...
}
...
```

{% endraw %}

In the above PowerShell script, I inspect the Docker container low-level information and extract just the **State.Health.Status** property and check whether its value is the *healthy* string; if it is, this means the container has entered the healthy state which means that the database has reached its ready state. Of course, the script does a lot more, but these lines are the most important ones in regards to health checking approach.

<!-- markdownlint-disable MD033 -->
<h4 id="identify-database-port">Identify database port</h4>
<!-- markdownlint-disable MD033 -->

Service containers [offer](#using-container-port) the means of identifying the Docker host ports associated with a container, but when using self-managed containers, well, one must also self-identify these ports.  
Both aforementioned PowerShell scripts used for running Docker containers also include the logic of identifying the Docker host ports by making use of the [docker port](https://docs.docker.com/engine/reference/commandline/port/) command.  
This command requires the Docker container port and the container name and will return the host port:

```powershell
docker port db4it 5432/tcp
# 0.0.0.0:50108
```

In the above command, I'm asking Docker sever to provide the host port allocated for the container named *db4it* which processes *TCP* packets received on port *5432* - the response is *50108*.  
This means any process running on that Docker host needs to communicate with the dockerized process via port 50108 - thus, the `dotnet test` command used for running integration tests needs to use a [PostgreSQL connection string](https://www.npgsql.org/doc/connection-string-parameters.html) where the port is set to **50108**:

```powershell
Host=localhost; Port=50108; Database=db4it; Username=satrapu; Password=***;
```

Both log-polling and healthcheck related PowerShell scripts make use of a parameter named *$PortMapping* used for [publishing ports](https://docs.docker.com/config/containers/container-networking/#published-ports); knowing the Docker container port (e.g. 5432), one can identify the Docker host port:

```powershell
...
$dockerContainerPort = $PortMapping

if ($PortMapping -like '*:*') {
    $dockerContainerPort = $PortMapping -split ':' | Select-Object -Skip 1
}

$dockerHostPort = docker port $ContainerName $dockerContainerPort
$dockerHostPort = $dockerHostPort -split ':' | Select-Object -Skip 1
Write-Output "##vso[task.setvariable variable=$DockerHostPortBuildVariableName]$dockerHostPort"
...
```

Since `docker port` command is able to handle various forms of Docker container ports, the above script must also consider them:

| $PortMapping Format                                   | $PortMapping Example | Docker Command Example       |
| ----------------------------------------------------- | -------------------- | ---------------------------- |
| \<JUST_THE_CONTAINER_PORT\>                           | 5432                 | docker port db4it *5432*     |
| \<CONTAINER_PORT_AND_NETWORK_PROTOCOL\>               | 5432/tcp             | docker port db4it *5432/tcp* |
| \<HOST_PORT\>:\<CONTAINER_PORT_AND_NETWORK_PROTOCOL\> | 9876:5432/tcp        | docker port db4it *5432/tcp* |

**IMPORTANT:** The above script fragment makes use of the so-called Azure DevOps [logging commands](https://docs.microsoft.com/en-us/azure/devops/pipelines/scripts/logging-commands?view=azure-devops&tabs=powershell) in order to [set a build variable](https://docs.microsoft.com/en-us/azure/devops/pipelines/scripts/logging-commands?view=azure-devops&tabs=powershell#setvariable-initialize-or-modify-the-value-of-a-variable) to the Docker host port so that the next build steps might use it - for instance the build step used for replacing the port placeholder found inside the database connection string with an actual port value. More precisely, the build variable whose name is stored inside the script parameter *$DockerHostPortBuildVariableName* will be set to the actual Docker host port (e.g. 50108).  
Please note each build agent will map Docker container port 5432 to a different value!

<!-- markdownlint-disable MD033 -->
<h4 id="update-database-connection-string">Update database connection string</h4>
<!-- markdownlint-disable MD033 -->

Now that the Docker host port allocated to the dockerized database is known, I can update the database connection string so that its port will be correctly set by replacing the placeholder *\_\_DockerHostPort\_\_* with the value of the appropriate build variable:

{% raw %}

```yaml
...
# Runs a PowerShell script to ensure the connection string pointing to the database
# to be targeted by the integration tests uses the appropriate port.
- task: PowerShell@2
  inputs:
    targetType: 'inline'
    errorActionPreference: 'stop'
    script: |
      Write-Output "The Docker host port mapped to container '${{ parameters.db4it.dockerContainerName }}' is: $(${{ parameters.db4it.dockerHostPortBuildVariableName }})"
      $normalizedDatabaseConnectionString = "${{ parameters.db4it.databaseConnectionString.value }}" -replace '${{ parameters.db4it.databaseConnectionString.portPlaceholder }}', $(${{ parameters.db4it.dockerHostPortBuildVariableName }})
      Write-Output "##vso[task.setvariable variable=DatabaseConnectionStrings.Todo]$normalizedDatabaseConnectionString"
      Write-Output "The normalized database connection string is: $normalizedDatabaseConnectionString"
  name: normalize_db_connection_string_pointing_to_db4it
  displayName: Normalize database connection string pointing to db4it Docker container
  enabled: True
...
```

The above **$(${{ parameters.db4it.dockerHostPortBuildVariableName }})** notation points to a build variable whose name is given by the job parameter **parameters.db4it.dockerHostPortBuildVariableName**. The same job parameter was used as an input parameter to the PowerShell scripts running the dockerized databases to ensure the Docker host port is passed from one build step to another without using a hard-coded build variable name (yes, I know this looks like over-engineering, but I *really* wanted to experiment with Azure DevOps pipelines, especially with their build variables).

{% endraw %}

The above inline PowerShell script will create a new build variable *DatabaseConnectionStrings.Todo* and set its value to the updated database connection string, e.g. `Host=localhost; Port=50108; Database=db4it; Username=satrapu; Password=***;`; then, this variable will be used by the next build step - running integration tests.

<!-- markdownlint-disable MD033 -->
<h2 id="run-integration-tests">Run integration tests</h2>
<!-- markdownlint-disable MD033 -->

In order to run integration tests, I need to ensure the connection string pointing to the containerized PostgreSQL database is available as an environment variable under the same name as the code expects it - and that is __Todo__, as seen below:

```cs
...
services.AddDbContext<TodoDbContext>((serviceProvider, dbContextOptionsBuilder) =>
{
    var connectionString = Configuration.GetConnectionString("Todo");
    dbContextOptionsBuilder.UseNpgsql(connectionString)
                           .EnableSensitiveDataLogging()
                           .UseLoggerFactory(serviceProvider.GetRequiredService<ILoggerFactory>());
});
...
```

The pipeline will run integration tests by using a [script](https://docs.microsoft.com/en-us/azure/devops/pipelines/scripts/cross-platform-scripting?view=azure-devops&tabs=yaml) accompanied by the appropriate environment variables, among them being __CONNECTIONSTRINGS__TODO__:

{% raw %}

```yaml
- script: >-
      dotnet test $(Build.SourcesDirectory)/Todo.sln
      --no-build
      --configuration ${{ parameters.build.configuration }}
      --filter "Category=IntegrationTests"
      --test-adapter-path "."
      --logger "nunit"
      /p:CollectCoverage=True
      /p:CoverletOutputFormat=opencover
      /p:Include="[Todo.*]*"
      /p:Exclude="[Todo.*.*Tests]*"
    name: run_integration_tests
    displayName: Run integration tests
    enabled: True
    env:
      DOTNET_SKIP_FIRST_TIME_EXPERIENCE: $(DotNetSkipFirstTimeExperience)
      DOTNET_CLI_TELEMETRY_OPTOUT: $(DotNetCliTelemetryOptOut)
      COREHOST_TRACE: $(CoreHostTrace)
      CONNECTIONSTRINGS__TODO: $(DatabaseConnectionStrings.Todo)
```

{% endraw %}

In case you're wondering why the environment variable is named __CONNECTIONSTRINGS__TODO__, while the application expects a connection string named __Todo__, the answer is that this is an ASP.NET Core naming convention, as detailed inside the [official documentation](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/configuration/?view=aspnetcore-2.2#keys).

<!-- markdownlint-disable MD033 -->
<h3 id="comparison">Service containers vs. self-managed containers</h3>
<!-- markdownlint-disable MD033 -->

OK, so now we can use either [service containers](#service-containers) or [self-managed containers](#self-managed-docker-containers), but when and why should we favor one over the other?  
Below I have assembled several scenarios and my personal view over the recommended solutions, along with their trade-offs.

| Scenario                                            | Service Containers | Self-Managed Containers |
| --------------------------------------------------- | ------------------ | ----------------------- |
| Use Microsoft-hosted agents                         | Recommended        | Recommended*            |
| Use self-hosted agents                              | Recommended**      | Recommended             |
| Favor simplicity                                    | Recommended        | Not recommended         |
| Favor more control                                  | Not recommended    | Recommended             |
| Favor fail fast builds***                           | Not recommended    | Recommended             |
| The build **must** run on macOS                     | Not supported      | Recommended             |
| I only use Windows based agents                     | Recommended        | Recommended*            |
| I only use Linux based agents                       | Recommended        | Recommended*            |
| I use both Linux and Windows based agents           | Recommended        | Recommended*            |
| Whatever, just run some containers during the build | Recommended        | Recommended*            |

\* Need extra setup effort, as explained above, but keep in mind using Docker Compose will greatly simplify things!  
\** Linux and Windows based agents only  
\*** A fail fast build means I will not first pull a Docker image (usually a slow build step), like service containers do, and then see unit tests fail (usually a  very fast build step); I will rather run unit tests and *if* they pass, only then will I pull the Docker image and run integration tests
  
<!-- markdownlint-disable MD033 -->
<h2 id="other-challenges">Other challenges</h2>
<!-- markdownlint-disable MD033 -->

While developing the Azure DevOps pipeline presented during this post, I have encountered several challenges and I believe documenting them might actually help others too.

<!-- markdownlint-disable MD033 -->
<h3 id="run-postgresql-locally-using-docker">Run PostgreSQL database locally using Docker</h3>
<!-- markdownlint-disable MD033 -->

As mentioned by me [earlier](#db-for-azure-pipelines), *"the developer and Azure Pipelines can use the same Docker image"*, so I run the following line to start a Docker container hosting PostgreSQL 12:

```powershell
docker container run `
       --name db4it `
       -d `
       --restart unless-stopped `
       -e POSTGRES_DB=aspnet-core-logging-dev `
       -e POSTGRES_USER=satrapu `
       -e POSTGRES_PASSWORD=F*ZMNJDWfr4%RFM `
       -p 9876:5432 `
       -v E:\Satrapu\Programming\docker-volumes\db4it_data:/var/lib/postgresql/data `
       postgres:12-alpine
```

I was sure that this command will start the database, but to my surprise, the database was not accessible. Checking the container log file I've stumbled upon the following lines:

```text
...
creating configuration files ... ok
2019-12-27 15:29:34.575 UTC [50] FATAL:  data directory "/var/lib/postgresql/data" has wrong ownership
2019-12-27 15:29:34.575 UTC [50] HINT:  The server must be started by the user that owns the data directory.
child process exited with exit code 1
initdb: removing contents of data directory "/var/lib/postgresql/data"
```

This is a [known issue](https://github.com/docker-library/postgres/issues/435) and the fix is to use a Docker volume created via [docker volume create](https://docs.docker.com/engine/reference/commandline/volume_create/) command and then start the container with this newly volume, like this:

```powershell
docker volume create db4it_data; `
docker container run `
       --name db4it `
       -d `
       --restart unless-stopped `
       -e POSTGRES_DB=aspnet-core-logging-dev `
       -e POSTGRES_USER=satrapu `
       -e POSTGRES_PASSWORD=F*ZMNJDWfr4%RFM `
       -p 9876:5432 `
       -v db4it_data:/var/lib/postgresql/data `
       postgres:12-alpine
```

I haven't encounter this issue while running the build on Azure DevOps since I'm not using any Docker volumes as I have decided to simplify my Docker container setup. On the other hand, if I were to use self-hosted agents and re-use persistent data between builds (e.g. run a Docker container to populate the database schema once per build and then run a container per test using the volume with the already created schema), I would have definitely used Docker volumes!

<!-- markdownlint-disable MD033 -->
<h3 id="publish-test-results">Fix publishing test results</h3>
<!-- markdownlint-disable MD033 -->

After refactoring the application to replace the in-memory EF Core provider with Npgsql, I was stunned seeing that even if I had added more tests and thus had increased the code coverage percentage, Sonar would complain that my changes have less than the expected code coverage threshold of 80%. After investigating for a while, I've discovered that the xUnit test results files for the unit tests did not contain any method and they all look like this:

```xml
<?xml version="1.0" encoding="utf-8"?>
<test-run id="2" duration="0" testcasecount="0" total="0"
          passed="0" failed="0" inconclusive="0" skipped="0" result="Passed"
          start-time="2019-06-09T 18:39:42Z"
          end-time="2019-06-09T 18:39:45Z" />
```

Initially I thought using xUnit is the culprit and I have refactored all my tests to use [NUnit](https://nunit.org/) instead, but to no avail. By the way, this is the reason why the [previous article](https://crossprogramming.com/2019/03/17/build-asp-net-core-app-using-azure-pipelines.html#run-automated-tests) was mentioning xUnit, while this one mentions NUnit.  
To keep the story short, I have [contacted](https://twitter.com/satrapu/status/1137795889085538304) Azure DevOps Twitter account and got to the bottom of the issue: since I was running 2 test sessions, one for unit tests and another one for integration tests, my publish test results [task](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/test/publish-test-results?view=azure-devops&tabs=yaml) would only publish the results of the __last__ session - the one containing the integration tests. The fix was pretty easy: call this task after __each__ test session:

{% raw %}

```yaml
...
# Run unit tests
- script: >-
      dotnet test $(Build.SourcesDirectory)/Todo.sln
      --no-build
      --configuration ${{ parameters.build.configuration }}
      --filter "Category=UnitTests"
      ...

# Publish unit tests results
- task: PublishTestResults@2
  displayName: Publish unit test results
  name: publish_unit_test_results
  condition: succeededOrFailed()
  enabled: True
  inputs:
    testResultsFormat: 'NUnit'
    testResultsFiles: '**/UnitTests/**/TestResults/*'
    mergeTestResults: True
    buildConfiguration: ${{ parameters.build.configuration }}
    publishRunAttachments: True

# Run integration tests
- script: >-
    dotnet test $(Build.SourcesDirectory)/Todo.sln
    --no-build
    --configuration ${{ parameters.build.configuration }}
    --filter "Category=IntegrationTests"
    ...

# Publish integration tests results
- task: PublishTestResults@2
  displayName: Publish integration test results
  name: publish_integration_test_results
  condition: succeededOrFailed()
  enabled: True
  inputs:
    testResultsFormat: 'NUnit'
    testResultsFiles: '**/IntegrationTests/**/TestResults/*'
    mergeTestResults: True
    buildConfiguration: ${{ parameters.build.configuration }}
    publishRunAttachments: True
...
```

{% endraw %}

Moral of the story: do not waste way too much time looking for a solution, show some courage and use professional help.  
Many thanks to [AzureDevOps](https://twitter.com/AzureDevOps) for their quick help!

<!-- markdownlint-disable MD033 -->
<h3 id="publish-raw-test-results-as-artifacts">Publish test results raw files as pipeline artifacts</h3>
<!-- markdownlint-disable MD033 -->

As mentioned above, after adding more tests, my code coverage was below the expected minimum threshold, so I decided to check the raw XML file containing the test results, files which are generated when running ```dotnet test``` command with the appropriate parameters.  
In order to access these files, I had to publish them as pipeline artifacts using the approach described [here](https://docs.microsoft.com/en-us/azure/devops/pipelines/artifacts/pipeline-artifacts?view=azure-devops&tabs=yaml-task#publish-a-pipeline-artifact) - since in the future I might desire publishing other build artifacts as well, I've decided to document this process for future references.  
The pipeline YAML file contains a [task](https://docs.microsoft.com/en-us/azure/devops/pipelines/artifacts/pipeline-artifacts?view=azure-devops&tabs=yaml-task#publish-a-pipeline-artifact) which will handle publishing artifacts:

{% raw %}

```yaml
...
- task: PublishPipelineArtifact@1
    displayName: Publish test results as pipeline artifacts
    name: publish_test_results_as_pipeline_artifacts
    condition: |
      and
      (
          succeededOrFailed()
        , eq( ${{ parameters.publishPipelineArtifacts }}, True)
      )
    inputs:
      artifact: 'test-results-$(Agent.OS)-$(Agent.OSArchitecture)'
      path: '$(Build.SourcesDirectory)/Tests'
...
```

{% endraw %}

The artifacts would be named like this (see more here: [Agent variables](https://docs.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#agent-variables)):

| OS      | Name                            |
| ------- | ------------------------------- |
| Linux   | test-results-Linux-X64.zip      |
| macOS   | test-results-Darwin-X64.zip     |
| Windows | test-results-Windows_NT-X64.zip |

Since the tests might fail, I have ensured the raw test result files will always be published by specifying the *[succeededOrFailed()](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/expressions?view=azure-devops#succeededorfailed)* condition.  
Secondly, I had to specify the exact files to publish by using an [.artifactignore](https://github.com/satrapu/aspnet-core-logging/blob/cb97b1604549b1519b31cfa6f42c33d545564924/Tests/.artifactignore#L1) file placed under the [Tests](https://github.com/satrapu/aspnet-core-logging/tree/master/Tests) folder:

```gitignore
**/*
!**/TestResults/*
!**/coverage.opencover.xml
```

This file instruct Azure Pipeline to ignore *all* files and to publish only those located inside the __TestResults__ folder or whose name is __coverage.opencover.xml__, as I wanted to check the Coverlet output too.  
See more about the .artifactignore file [here](https://docs.microsoft.com/en-us/azure/devops/pipelines/artifacts/pipeline-artifacts?view=azure-devops&tabs=yaml-task#limiting-which-files-are-included).

__IMPORTANT__: Using this approach, one might publish *any* kind of files as pipeline artifacts, as long as they are located under the current workspace, no matter whether they are static (part of the checked-out repository) or dynamic (generated during the build).

<!-- markdownlint-disable MD033 -->
<h2 id="next-steps">Next steps</h2>
<!-- markdownlint-disable MD033 -->

As seen above, running just *one* Docker container needs a not trivial amount of effort, so what happens in case the build needs to use more containers?  
The answer is using an *orchestration engine* and what better option than using [Docker Compose](https://docs.docker.com/compose/)?  
The Linux and Windows based agents already come with Docker Compose installed, while Docker Desktop for Mac [contains](https://docs.docker.com/compose/install/#install-compose) it too. Docker Compose will greatly simplify the whole container setup, as starting several containers will be reduce to something as simple as: `docker-compose up`.  
This post is already *very* long, so most probably I will demonstrate using Docker Compose inside an Azure DevOps pipeline in a future post.

<!-- markdownlint-disable MD033 -->
<h2 id="conclusion">Conclusion</h2>
<!-- markdownlint-disable MD033 -->
Ensuring your application behaves as expected is crucial to everybody involved in developing it - be it a developer, tester, business analyst, you name it - and writing automated tests is just one step for achieving this goal - you still need other types of testing, like: exploratory testing, security testing, performance testing and others, and let's not forget about deploying the application to several environments (e.g. integration, test, pre-production) and running smoke tests on each one of them before finally pushing the release to production and running the smoke tests there too.  
Being able to run integration tests as part of the build which validates each commit is a __must__ and employing Docker to host all your test dependencies is easier and cheaper than using virtual machines or other external resources and lowers the integration tests adoption barrier for all team members. On the other hand, this doesn't eliminate the need of testing the application in a close-to or cloned production environment, but will provide important feedback about its behavior way before reaching that point.
