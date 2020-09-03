---
layout: post
title: "Use Docker Compose when running integration tests with Azure Pipelines"
date: 2020-09-03 10:18:07 +0200
tags: [programming, dotnet, dotnet-core, aspnet-core, azure-devops, azure-pipeline, integration-tests, docker, docker-compose, postgresql, linux-containers, windows-containers]
---

- [Context](#context)
- [Why should I use Docker Compose?](#motivation)
- [Solution high-level view](#solution-high-level-view)
- [Solution low-level view](#solution-low-level-view)
  - [Install Docker on macOS-based agents](#install-docker-on-macos)
  - [Run PowerShell script](#run-powershell-script)
  - [Prepare compose environment variables](#prepare-compose-environment-variables)
  - [Start compose service](#start-compose-service)
  - [Identify compose service metadata](#identify-compose-service-metadata)
    - [Identify container ID](#identify-container-id)
    - [Identify compose service name](#identify-compose-service-name)
  - [Wait for compose service to become healthy](#wait-for-compose-service)
  - [Identify compose service host port](#identify-host-port)
  - [Expose host port as a pipeline variable](#expose-host-port-as-pipeline-variable)
  - [Run integration tests](#run-integration-tests)
- [Issues](#issues)
  - [Compose file version](#compose-file-version)
  - [Docker Compose writes to standard error stream](#docker-compose-writing-to-sdterr)
  - [Unstable Windows Docker image](#unstable-windows-docker-image)
- [Other use cases](#other-use-cases)
- [Conclusion](#conclusion)

* * *
<!-- markdownlint-disable MD033 -->
<h2 id="context">Context</h2>

In my previous Azure DevOps related [post](https://crossprogramming.com/2019/12/27/use-docker-when-running-integration-tests-with-azure-pipelines.html) I have presented two approaches for running integration tests targeting a PostgreSQL database hosted in a Docker container:

- [Service containers](https://crossprogramming.com/2019/12/27/use-docker-when-running-integration-tests-with-azure-pipelines.html#service-containers) - these containers run on Linux and Windows-based only agents
- [Self-managed containers](https://crossprogramming.com/2019/12/27/use-docker-when-running-integration-tests-with-azure-pipelines.html#self-managed-docker-containers) - these containers run on Linux, macOS and Windows-based agents.  

This post has several goals:

- Run the same tests against the same database, but this time using [Docker Compose](https://docs.docker.com/compose/) instead of plain Docker containers
- Run Docker Compose on Linux, macOS and Windows-based agents
- Create a generic solution capable of running various compose workloads

The source code used by this post can be found here: [feature/use-docker-compose-for-it](https://github.com/satrapu/aspnet-core-logging/tree/feature/use-docker-compose-for-it).

<h2 id="motivation">Why should I use Docker Compose?</h2>

Using Docker Compose for orchestrating services needed to run integration tests instead of plain Docker containers provides several advantages:

- **Simpler Azure Pipeline**: Docker Compose allows orchestrating several containers using one [compose file](https://docs.docker.com/compose/compose-file/), so I only need one build step in my Azure Pipeline to ensure all services needed to run my tests are up & running, while using plain Docker containers for the same goal means defining one build step per container; additionally, declaring more services in the compose file does not need declaring extra build steps
- **Avoid "Works on My Machine" syndrome**: I can run the compose services on my development machine, thus ensuring both developer and Azure Pipeline have the same experience when running integration tests; this can also be achieved using plain Docker containers, but with more effort, since you need to run one `docker container run` command per service and optionally setting up other things like: volumes, networks, etc.
- **Shorter feedback loop**: If I change anything in the compose file, I can quickly run `docker-compose up` and verify whether everything still works as expected, without the need to re-run my entire CI pipeline

<h2 id="solution-high-level-view">Solution high-level view</h2>

My solution to using Docker Compose when running integration tests with Azure Pipelines consists of [one compose file](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/db4it-compose/docker-compose.yml) (pretty obvious, since I want to run Docker Compose) and [one PowerShell script](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/RunComposeServices.ps1).  
This script [starts](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/RunComposeServices.ps1#L93-L96) the compose service declared inside the compose file and will periodically [poll](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/RunComposeServices.ps1#L160-L162) the service to check whether it has reached its [declared health state](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/db4it-compose/docker-compose.yml#L9-L19). Once the service is healthy (ready to handle incoming connections to the PostgreSQL database), the script will also [register](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/RunComposeServices.ps1#L257-L258) a variable storing the host port mapped by Docker to the container port (that is 5432 for a PosgreSQL database), so that the following build steps might have the chance of interacting with the database using  this port. When the build step used for running the integration tests starts, it will [pass](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/azure-pipelines.job-template.yml#L250-L255) the connection string (having [its port](http://www.npgsql.org/doc/connection-string-parameters.html) set to the previously identified host port) pointing to the database as an environment variable to the `dotnet test` command (similar to the approach documented in the [previous post](https://crossprogramming.com/2019/12/27/use-docker-when-running-integration-tests-with-azure-pipelines.html#run-integration-tests)) and when the tests run, they will be able to communicate with a running database.  

**IMPORTANT**: Since my CI pipeline is currently using Docker containers for running tests only, my compose file does not declare any Docker volume! Based on your scenarios, you might need to declare such volumes in your compose file.

<h2 id="solution-low-level-view">Solution low-level view</h2>

<h3 id="install-docker-on-macos">Install Docker on macOS-based agents</h3>

In order to be able to run a compose workload on a macOS-based Azure DevOps agents, I only need to install Docker for macOS, as already documented on my [previous post](https://crossprogramming.com/2019/12/27/use-docker-when-running-integration-tests-with-azure-pipelines.html#run-docker-on-macos) - the Docker package I'm using includes Docker Compose - sweet!

<h3 id="run-powershell-script">Run PowerShell script</h3>

The first step for starting the compose workload in my pipeline is [running](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/azure-pipelines.job-template.yml#L204-L229) the aforementioned PowerShell script using an [PowerShell@2](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/utility/powershell?view=azure-devops) Azure DevOps task:

{% raw %}

```yaml
- task: PowerShell@2
    name: 'start_compose_services_used_by_integration_tests'
    displayName: 'Start compose services used by integration tests'
    inputs:
      targetType: 'filePath'
      filePath: '$(Build.SourcesDirectory)/Build/RunComposeServices.ps1'
      arguments: ...
      errorActionPreference: 'Continue'
      failOnStderr: False
      workingDirectory: $(Build.SourcesDirectory)
```

{% endraw %}

Check the [section below](#docker-compose-writing-to-sdterr) in order to understand the reason behind setting the **errorActionPreference** and **failOnStderr** to the particular values from above.

<h3 id="prepare-compose-environment-variables">Prepare compose environment variables</h3>

My compose file looks something like this (some details were omitted for brevity):

```yaml
version: "3.7"

services:
  db4it:
    image: "${db_docker_image}"
    ...
    environment:
      POSTGRES_DB: "${db_name}"
      POSTGRES_USER: "${db_username}"
      POSTGRES_PASSWORD: "${db_password}"
    ports:
      - 5432
```

The file above contains one service, **db4it**, along with several other variables, like: **${db_docker_image}**, **${db_password}**, etc., which need to be replaced with actual values before the compose service starts.  
In order to replace **${db_docker_image}**, which represents the name of the PostgreSQL Docker image, and since I want to run a compose workload on various Azure DevOps agents which will run PostgreSQL as Linux and Windows containers, I have several options:

- Create 2 compose files: one for running PostgreSQL as a Linux container and another one for running PostgreSQL as a Windows container
- Use a parameterized compose file and replace each parameter with an environment variable at run time
- Some other option?

Since Docker Compose [knows](https://docs.docker.com/compose/environment-variables/) how to handle environment variables and since I'm already using job parameters, I've chosen the second option. Another reason (maybe the most important one) is that storing sensitive pieces of information in files put under source control is a security risk, so I'm not going to include the database password inside the compose file, but store it as an Azure DevOps [secret variable](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/variables?view=azure-devops&tabs=yaml%2Cbatch#secret-variables) and pass it to the script used for starting compose services as a [parameter](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/azure-pipelines.yml#L89).

Before Docker Compose starts running the service, it will search various places in order to find all values it can use for replacing the appropriate variables. My PowerShell script has two optional parameters allowing specifying such variables which will be promoted to environment variables, thus enabling Docker Compose to find and use them in the compose file.
One such parameter represents the relative path to a [.env file](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/db4it-compose/.env), while the second one represents a hash table where variables are provided as key-value pairs; one could use both or just one of them for specifying the compose variables. I have used the .env file for storing non-sensitive key-value pairs, since this file is put under [source control](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/db4it-compose/.env); on the other hand, I have used the hash table for sensitive ones (e.g. the ${db_password} value).  
Please note that the key-value pairs found inside the hash table override the ones found inside the .env file - this is by design.

Passing the relative path to the .env file (to be [resolved](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/RunComposeServices.ps1#L49-L56) considering the current script path as base path) and the key-value pairs as parameters to this script is done via:

{% raw %}

```yaml
- task: PowerShell@2
    name: 'start_compose_services_used_by_integration_tests'
    displayName: 'Start compose services used by integration tests'
    inputs:
      ...
      arguments: >-
        -ComposeProjectName '${{ parameters.integrationTests.composeProjectName }}' `
        -RelativePathToComposeFile './db4it-compose/docker-compose.yml' `
        -RelativePathToEnvironmentFile './db4it-compose/.env' `
        -ExtraEnvironmentVariables `
         @{ `
           'db_docker_image'='${{ parameters.integrationTests.databaseDockerImage }}'; `
           'db_name'='${{ parameters.integrationTests.databaseName }}'; `
           'db_username'='${{ parameters.integrationTests.databaseUsername }}'; `
           'db_password'='${{ parameters.integrationTests.databasePassword }}'; `
         }
      ...
```

{% endraw %}

I'm passing the hash table as PowerShell parameter using `@{key1 = value1; key2 = value2; ...}` construct; please note that I've used the ` (tick) symbol to keep each key-value pair on a separate line to increase code readability.  
See more about working with hash tables in PowerShell [here](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_hash_tables?view=powershell-7).

Declaring an environment variable in PowerShell is as simple as this:

```powershell
[System.Environment]::SetEnvironmentVariable($EnvironmentVariableName, $EnvironmentVariableValue, 'Process')
```

Please note the `'Process'` string passed as the 3rd parameter - this means that the key-value pairs will be [visible](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/RunComposeServices.ps1#L58-L84) to the compose workload which will be started as a stand alone process several lines below inside the aforementioned PowerShell script.  

See more about working with environment variables in PowerShell [here](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7) and see more about Docker Compose .env files [here](https://docs.docker.com/compose/environment-variables/#the-env-file).

<h3 id="start-compose-service">Start compose service</h3>

Once the environment variables have been setup, starting the compose service is done using [docker-compose up](https://docs.docker.com/compose/reference/up/) command:

```powershell
docker-compose --file="$ComposeFilePath" `
               --project-name="$ComposeProjectName" `
               up `
               --detach
```

The **--file** argument represents the full path to the compose file which has been [calculated](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/RunComposeServices.ps1#L40-L47) by combining the full path to the current script and the relative path to the compose file passed as a [parameter](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/azure-pipelines.job-template.yml#L213); see more about this argument [here](https://docs.docker.com/compose/reference/overview/#specifying-a-path-to-a-single-compose-file).  
The **--project-name** argument is needed in order to separate this particular compose workload from others running on the same Docker host; think of this project name like a namespace in C# or package in Java; see more about this argument [here](https://docs.docker.com/compose/reference/overview/#use--p-to-specify-a-project-name).  
The **--detach** argument is needed to ensure the compose service is run in the background since I want to run the tests against it using the following build step.

<h3 id="identify-compose-service-metadata">Identify compose service metadata</h3>

In order to be able to correctly determine whether the compose service has reached its healthy state, I need to identify its container ID assigned by Docker and its compose service name declared inside the compose file.  

You might say: *Hey, but I already know the name of the compose service, since it's found inside the compose file!* and you would be right, but do you also remember I said one of the goals of this post is *Create a generic solution capable of running various compose workloads*? Due to this reason, the PowerShell script cannot assume any service names and it has to resort to several Docker commands to identify the two pieces of information with extra help coming from the labels automatically added by Docker when creating a container for a Docker Compose service.

<h4 id="identify-container-id">Identify container ID</h4>
At this point, I know that the compose service is running, so I can request the container ID from Docker using the [docker container ls](https://docs.docker.com/engine/reference/commandline/container_ls/) command since each compose service is in fact a Docker container; on the other hand, if my pipeline is running several Docker containers, I cannot tell which one is the one I'm interested in, so I need to [filter](https://docs.docker.com/engine/reference/commandline/ps/#filtering) the outcome of the aforementioned Docker command and that's the reason I'm using the **--project-name** when starting the compose service.  
Using filters, I can limit the search to only those Docker containers belonging to [my compose project](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/azure-pipelines.job-template.yml#L212):

{% raw %}

```powershell
$LsCommandOutput = docker container ls -a `
                                    --filter "label=com.docker.compose.project=$ComposeProjectName" `
                                    --format "{{ .ID }}" `
                                    | Out-String
```

{% endraw %}

The command above will return only the ID of the Docker container running the PostgreSQL database to be targeted by my integration tests. In case my compose workload would have more than one service, there will be returned one container ID per such service.

<h4 id="identify-compose-service-name">Identify compose service name</h4>
In order to identify the name of the compose service as I have declared inside the compose file (db4it), I have to extract the value of the label **com.docker.compose.service** accompanying the Docker container whose ID I already know.  
I first need to ask Docker for all labels using [docker container inspect](https://docs.docker.com/engine/reference/commandline/container_inspect/) command:

{% raw %}

```powershell
$ComposeServiceLabels = docker container inspect --format '{{ json .Config.Labels }}' `
                                                 $ContainerId `
                                                 | Out-String `
                                                 | ConvertFrom-Json
```

 {% endraw %}

 The **$ComposeServiceLabels** variable will store a dictionary which looks something similar to this:

```powershell
 @{
    com.docker.compose.config-hash=f19c28a66cb2fc63a18618d87ae96b532f582acd310b297a2647d2e92c7ab34d;
    com.docker.compose.container-number=1;
    com.docker.compose.oneoff=False;
    com.docker.compose.project=aspnet-core-logging;
    com.docker.compose.project.config_files=docker-compose.yml;
    com.docker.compose.project.working_dir=/mnt/c/Dev/Projects/aspnet-core-logging;
    com.docker.compose.service=aspnet-core-logging-dev;
    com.docker.compose.version=1.26.2;
    desktop.docker.io/wsl-distro=Ubuntu
}

```

The output above is just an example as my compose service will have different values for the above keys.  
Extracting the name of the compose service from the above dictionary is as simple as:

```powershell
$ComposeServices = [System.Collections.Generic.List[psobject]]::new()
...
$ComposeServiceNameLabel = 'com.docker.compose.service'
$ComposeServiceName = $ComposeServiceLabels.$ComposeServiceNameLabel

$ComposeService = New-Object PSObject -Property @{
    ContainerId = $ContainerId
    ServiceName = $ComposeServiceName
}

$ComposeServices.Add($ComposeService)
```

The above PowerShell script fragment puts both container ID and service name in a custom object which will be stored in a list ($ComposeServices) for later use.

<h3 id="wait-for-compose-service">Wait for compose service to become healthy</h3>

Once I know the ID of the Docker container running the PostgreSQL database, I can check whether the container has reached its healthy state using something like this:

{% raw %}

```powershell
$IsServiceHealthy = docker container inspect "$($ComposeService.ContainerId)" `
                                             --format "{{.State.Health.Status}}" `
                                             | Select-String -Pattern 'healthy' -SimpleMatch -Quiet
```

If the value of the **$IsServiceHealthy** PowerShell variable is **$true**, then the compose service is healthy.  
The logic of checking for healthy state is more complex than the above script fragment, but you can always inspect the full version [here](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/RunComposeServices.ps1#L151-L194).

{% endraw %}

<h3 id="identify-host-port">Identify compose service host port</h3>

At this point, I know that my compose service is healthy, so now I only need to identify the host port Docker has allocated to the container running PostgreSQL, container which has [exposed](https://github.com/satrapu/aspnet-core-logging/blob/feature/use-docker-compose-for-it/Build/db4it-compose/docker-compose.yml#L26-L27) port 5432.  

Considering that a pipeline might run several compose workloads, I recommend to avoid [specifying the host port](https://docs.docker.com/compose/compose-file/#ports) and let Docker [allocate](https://docs.docker.com/network/links/#connect-using-network-port-mapping) an ephemeral host port. Once I know the container ID, finding the host port mapped to a container port is not very complicated.

In order to find all port mappings for a given compose service, I'm going to use [docker container port](https://docs.docker.com/engine/reference/commandline/container_port/) command:

```powershell
$PortCommandOutput = docker container port "$($ComposeService.ContainerId)" | Out-String
```

Since my compose service **db4it** only exposes one port, the command output will only contain one port mapping, but since the PowerShell script is generic, let's assume my compose service exposes 5 ports: 5432, 6677, 7788, 8899 and 9900 - in this case, the command above will return 5 mappings as a multi-line string:

```text
5432/tcp -> 0.0.0.0:32772
6677/tcp -> 0.0.0.0:32771
7788/tcp -> 0.0.0.0:32770
8899/tcp -> 0.0.0.0:32769
9900/tcp -> 0.0.0.0:32768
```

Identifying the host port from each of the above mappings is just a matter of correctly splitting the above command output string using some particular delimiters:

{% raw %}

```powershell
$RawPortMappings = $PortCommandOutput.Split([System.Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries)

foreach ($RawPortMapping in $RawPortMappings)
{
    $RawPortMappingParts = $RawPortMapping.Split(' -> ', [System.StringSplitOptions]::RemoveEmptyEntries)
    $RawContainerPort = $RawPortMappingParts[0]
    $RawHostPort = $RawPortMappingParts[1]
    $ContainerPort = $RawContainerPort.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)[0]
    $HostPort = $RawHostPort.Split(':', [System.StringSplitOptions]::RemoveEmptyEntries)[1]
}
```

For instance, after processing the third entry, *5432/tcp -> 0.0.0.0:32771*, the Docker container port is **5432**, while the host port is **32771**.

{% endraw %}

<h3 id="expose-host-port-as-pipeline-variable">Expose host port as a pipeline variable</h3>

In order to connect to the PostgreSQL database running in a Docker container, I need to pass the aforementioned host port to the next build step from my pipeline and the natural way is to use a [user-defined variable](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/variables?view=azure-devops&tabs=yaml%2Cbatch#user-defined-variables). Since my aim is to create a generic solution for running Docker Compose in an Azure DevOps pipeline, I will create one such variable per host port and I'm going to use the following naming convention: `compose.project.<COMPOSE_PROJECT_NAME>.service.<COMPOSE_SERVICE_NAME>.port.<CONTAINER_PORT>`.  

| Token                    | Description                                                      | Sample value                   |
|--------------------------|------------------------------------------------------------------|--------------------------------|
| \<COMPOSE_PROJECT_NAME\> | Represents the compose project name                              | integration-test-prerequisites |
| \<COMPOSE_SERVICE_NAME\> | Represents the compose service name as declared in compose file  | db4it                          |
| \<CONTAINER_PORT\>       | Represents the Docker container port as declared in compose file | 5432                           |

Given that my compose service is named **db4it**, given that it has been started using **integration-test-prerequisites** as compose project and given that it exposes container port **5432**, the variable storing its host port will be named: **compose.project.integration-test-prerequisites.service.db4it.port.5432**.

Assuming my compose service exposes 5 ports: 5432, 6677, 7788, 8899 and 9900, then I would end up with 5 variables in my pipeline:

| Variable Name                                                          | Container port | Host port |
|------------------------------------------------------------------------|----------------|-----------|
| compose.project.integration-test-prerequisites.service.db4it.port.5432 | 5432           | 32772     |
| compose.project.integration-test-prerequisites.service.db4it.port.6677 | 6677           | 32771     |
| compose.project.integration-test-prerequisites.service.db4it.port.7788 | 7788           | 32770     |
| compose.project.integration-test-prerequisites.service.db4it.port.8899 | 8899           | 32769     |
| compose.project.integration-test-prerequisites.service.db4it.port.9900 | 9900           | 32768     |

Please note the above host ports might not be the ones you'll see if you run this pipeline, since Docker might allocate different ephemeral host ports on each run.

<h3 id="run-integration-tests">Run integration tests</h3>

At this point, the Azure DevOps pipeline has started a compose service which is healthy and its host port is now stored in a variable. The next build step is to run integration tests and let them know how can they reach the PostgreSQL database running in a Docker container:

{% raw %}

```yaml
- script: >-
      dotnet test $(Build.SourcesDirectory)/Todo.sln
      --no-build
      --no-restore
      --configuration ${{ parameters.build.configuration }}
      --test-adapter-path "."
      --logger "nunit"
      /p:CollectCoverage=True
      /p:CoverletOutputFormat=opencover
      /p:Include="[Todo.*]*"
      /p:Exclude=\"[Todo.*.*Tests]*,[Todo.Persistence]*.TodoDbContextModelSnapshot\"
      -- NUnit.Where="cat == IntegrationTests"
    name: 'run_integration_tests'
    displayName: 'Run integration tests'
    env:
      CONNECTIONSTRINGS__TODOFORINTEGRATIONTESTS: >-
        Host=${{ parameters.integrationTests.databaseHost }};
        Port=$(compose.project.${{ parameters.integrationTests.composeProjectName }}.service.db4it.port.5432);
        Database=${{ parameters.integrationTests.databaseName }};
        Username=${{ parameters.integrationTests.databaseUsername }};
        Password=${{ parameters.integrationTests.databasePassword }};
      GENERATEJWT__SECRET: $(IntegrationTests.GenerateJwt.Secret)
```

{% endraw %}

Please note the way **Port** property from the PostgreSQL connection string has been set to the aforementioned variable.

<h2 id="issues">Issues</h2>

<h3 id="compose-file-version">Compose file version</h3>

I had to use compose file version 3.7 and not a newer one since macOS-based Azure DevOps agents cannot run Docker versions compatible with v3.8+.  
I'm still waiting for being able to install a newer version of Docker on this kind of agent, but until then, I have to resort to an [older version](https://crossprogramming.com/2019/12/27/use-docker-when-running-integration-tests-with-azure-pipelines.html#run-docker-on-macos).

<h3 id="docker-compose-writing-to-sdterr">Docker Compose writes to standard error stream</h3>

Docker Compose commands write to standard error stream, thus tricking Azure DevOps into thinking the PowerShell script running compose service has failed, which isn't the case. Due to this [known limitation](https://github.com/docker/compose/issues/5590), I need to rely on [`$?` automatic variable](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables?view=powershell-7#section-1) in my script to detect failures. Thus, I need to set the `errorActionPreference` property of the PowerShell@2 Azure DevOps task to `Continue` and set `failOnStderr` property to `False` to avoid failing the build step and then manually handle the outcome of each command inside the script, like below:

{% raw %}

```powershell
...
$LsCommandOutput = docker container ls -a `
                                    --filter "label=com.docker.compose.project=$ComposeProjectName" `
                                    --format "{{ .ID }}" `
                                    | Out-String

if ((!$?) -or ($LsCommandOutput.Length -eq 0))
{
    Write-Output "##vso[task.LogIssue type=error;]Failed to identify compose services for project: $ComposeProjectName"
    Write-Output "##vso[task.complete result=Failed;]"
    exit 4;
}
...
```

{% endraw %}

<h3 id="unstable-windows-docker-image">Unstable Windows Docker image</h3>

The [stellirin/postgres-windows](https://hub.docker.com/r/stellirin/postgres-windows) Docker image I'm using when running Docker Compose on Windows-based agents works *almost* every time, but not *every* time, so the jobs running on this agent might fail and I need to re-run them. I'm truly thankful that such image exists and until I find better alternatives, re-running the jobs from time to time seems like a small price to pay.  
Unfortunately, finding such alternatives might become crucial in a not so far away future, since the GitHub repository backing this Docker image has been marked as [archived](https://github.com/stellirin/docker-postgres-windows#this-repository-is-archived) as the author no longer has the need for PostgreSQL as a Windows container.

<h2 id="other-use-cases">Other use cases</h2>

Other use cases for running Docker Compose in an Azure DevOps pipeline might be:

- Run several versions of the same database, for instance when trying to test whether your application is compatible with the latest version of SQL Server, but is also backward compatible with older versions, like SQL Server 2005 or 2008 R2
- Restore a database backup before running tests against that particular database, where we need one service for the database and another service tasked with (downloading and) restoring the backup
- Run functional tests, where we need to start the application with all of its dependencies and optionally run each supported browser in a separate Docker container with the help of a tool like [Selenium Hub](https://github.com/SeleniumHQ/docker-selenium/blob/trunk/docker-compose-v3.yml)
- Provision more services needed to run the tests, e.g. out-of-process cache
- Run mock services which simulate the activity of expensive/hard to create and/or use services (e.g. payment provider, credit card validation, etc.)
- Any use case where you're running at least one Docker container ;)

<h2 id="conclusion">Conclusion</h2>

I believe using Docker Compose for running various workloads instead of using plain Docker containers is the better choice since it's easier to use and it's more flexible. On the other hand, using Docker Compose means sharing the agent resources (CPU, RAM and disk) between the build and the compose services. For lightweight workloads, like the one presented in this post, this is not an issue, but if you want to run more heavyweight workloads, you'll need to use a more powerful container orchestrator like [Kubernetes](https://kubernetes.io/) and run the containers outside Azure DevOps agents. This approach would let Azure DevOps agents use their resources for running builds, but you'll need extra machines to host your [Kubernetes pods](https://kubernetes.io/docs/concepts/workloads/pods/), thus paying more, but getting more too.