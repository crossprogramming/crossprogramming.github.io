---
layout: post
title: "Build an ASP.NET Core application using Azure Pipelines"
date: 2019-03-17 22:32:13 +0200
tags: [programming, dotnet, dotnet-core, aspnet-core, azure-devops, azure-pipeline, code-coverage, coverlet, reportgenerator, sonar, sonarlint, xunit]
---

- [Context](#context)
- [Setup pipeline](#setup-pipeline)
  - [Sign up for Azure DevOps](#sign-up-for-azure-devops)
  - [Create an Azure DevOps organization](#create-an-azure-devops-organization)
  - [Create a public project](#create-a-public-project)
  - [Create pipeline](#create-pipeline)
  - [Paths in pipeline](#paths-in-pipeline)
  - [Use YAML block chomping indicator](#use-yaml-block-chomping-indicator)
  - [Run jobs on different operating systems](#run-jobs-on-different-operating-systems)
  - [Use templates](#use-templates)
  - [Use variables and variable groups](#use-variables-and-variable-groups)
  - [Use secrets](#use-secrets)
- [Build application](#build-application)
  - [Install .NET Core SDK](#install-net-core-sdk)
  - [Compile source code](#compile-source-code)
- [Run automated tests](#run-automated-tests)
  - [Setup test logger](#setup-test-logger)
  - [Run unit tests](#run-unit-tests)
  - [Run integration tests](#run-integration-tests)
  - [Publish test results](#publish-test-results)
- [Code coverage using Coverlet](#code-coverage-using-coverlet)
  - [Collect code coverage data](#collect-code-coverage-data)
  - [Install ReportGenerator .NET Core tool](#install-reportgenerator-net-core-tool)
  - [Generate code coverage HTML report using ReportGenerator](#generate-code-coverage-html-report-using-reportgenerator)
  - [Publish code coverage report](#publish-code-coverage-report)
- [Static code analysis using SonarQube](#static-code-analysis-using-sonarqube)
  - [SonarCloud](#sonarcloud)
  - [Setup SonarCloud account](#setup-sonarcloud-account)
  - [Use SonarCloud token during build](#use-sonarcloud-token-during-build)
  - [Install dotnet-sonarscanner tool](#install-dotnet-sonarscanner-tool)
  - [Run dotnet-sonarscanner tool](#run-dotnet-sonarscanner-tool)
  - [Upload static code analysis report](#upload-static-code-analysis-report)
  - [Use SonarLint](#use-sonarlint)
  - [Use SonarQube build breaker](#use-sonarqube-build-breaker)
- [Badges](#badges)
  - [Azure Pipeline status badge](#azure-pipeline-status-badge)
  - [Sonar quality gate badge](#sonar-quality-gate-badge)
- [Conclusion](#conclusion)
- [References](#references)

* * *

<!-- markdownlint-disable MD022 -->
<!-- markdownlint-disable MD002 -->
## Context
<!-- markdownlint-disable MD002 -->
<!-- markdownlint-disable MD022 -->

Developing free and open-source software (aka [FOSS](https://en.wikipedia.org/wiki/Free_and_open-source_software)) and hosting it on [GitHub](https://help.github.com/articles/create-a-repo/) is fun and provides the freedom to learn and experiment on your own terms, but at the same time this activity should be done carefully, as the source code may be viewed by lots of people and its quality level should be as high as possible (not saying as close as a closed-source one, since companies have a lot more resources than your ordinary FOSS developer), so what better way of reaching this level than using an automated build? What's better than this? Free automated builds!  
I was very happy to learn about Microsoft Azure Pipelines offering free builds to open source projects - see the original announcement [here](https://azure.microsoft.com/en-us/blog/announcing-azure-pipelines-with-unlimited-ci-cd-minutes-for-open-source/). The icing on the top was that the same announcement mentioned that GitHub [integrates](https://github.com/marketplace/azure-pipelines) with this service.  

The purpose of this article is to present how to build a .NET Core application [hosted on GitHub](https://github.com/satrapu/aspnet-core-logging) with Azure Pipelines. I have first talked about this .NET Core application in my previous post, [Logging HTTP context in ASP.NET Core](https://crossprogramming.com/2018/12/27/logging-http-context-in-asp-net-core.html).

## Setup pipeline

The term __pipeline__ used throughout this post means an Azure Pipelines instance made out of different jobs, each job containing one or more steps.
The pipeline can be created using either a visual designer or a YAML file - Microsoft [recommends](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started-designer?view=azure-devops&tabs=new-nav) using the latter approach, and, just coincidentally, so do I.  
I would use the visual designer approach to perform quick experiments and to discover the YAML fragment equivalent of a particular step.  
On the other hand, the YAML file offers several benefits over the visual designer:

- The file can be put under source control
  - We're now able to understand who's done what and - more important! - *why*
  - The changes can go through an official code-review process before they impact the build
  - We can also quickly rollback to a specific version in case of a bug requiring extensive fixing
  - The code can be easily shared via a link to the hosted YAML file
- Coolness factor - we're developers, so we get to *write code* to *build code*!

### Sign up for Azure DevOps

In case you already have signed up for Azure DevOps, skip this section; otherwise, follow [these steps](https://docs.microsoft.com/en-us/azure/devops/user-guide/sign-up-invite-teammates?view=azure-devops) to sign up for Azure DevOps.

### Create an Azure DevOps organization

In case you already have access to such an organization, skip this section; otherwise, follow [these steps](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/create-organization?view=azure-devops) to create a new organization.

### Create a public project

In case you already have such a project, skip this section; otherwise, follow [these steps](https://docs.microsoft.com/en-us/azure/devops/organizations/public/create-public-project?view=azure-devops) to create a new public project.

### Create pipeline

Follow [these steps](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started-yaml?view=azure-devops) to create a YAML file based pipeline or follow [these ones](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started-designer?view=azure-devops&tabs=new-nav) to create a pipeline using the visual designer.  

### Paths in pipeline

In order to correctly reference a file or folder found inside the repository or generated during the current build, use one of the following [predefined variables](https://docs.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml):  

- __$(Build.SourcesDirectory)__: the local path on the agent where your source code is downloaded
- __$(Agent.BuildDirectory)__: the local path on the agent where all folders for a given build pipeline are created

For instance, the Visual Studio solution file is hosted on GitHub at this path: [https://github.com/satrapu/aspnet-core-logging/blob/master/Todo.sln](https://github.com/satrapu/aspnet-core-logging/blob/master/Todo.sln); the pipeline steps referencing this file should then use: __$(Build.SourcesDirectory)/Todo.sln__.  
Similarly, accessing the __.sonarqube__ folder which contains the static code analysis related artifacts and which is generated inside the solution root folder should be referenced using: __$(Agent.BuildDirectory)/.sonarqube__.

### Use YAML block chomping indicator

Using .NET Core CLI tools sometimes requires specifying several parameters which may lead to long lines in the Azure Pipeline YAML files, like this one:  

```yaml
script:
  dotnet test $(Build.SourcesDirectory)/Todo.sln --no-build --configuration ${{ parameters.build.configuration }} --filter "FullyQualifiedName~UnitTests" --test-adapter-path "." --logger "xunit;LogFilePath=TodoWebApp.UnitTests.xunit.xml" /p:CollectCoverage=True /p:CoverletOutputFormat=opencover /p:CoverletOutput="TodoWebApp.UnitTests.opencover.xml" /p:Include="[TodoWebApp]*"
```

When trying to read and understand someone else's code is not fun having to do horizontal scrolling, so the YAML block chomping indicator is a real life saver - see more [here](https://stackoverflow.com/a/3790497).  
The above line becomes:

```yaml
script: >-
  dotnet test $(Build.SourcesDirectory)/Todo.sln
  --no-build
  --configuration ${{ parameters.build.configuration }}
  --filter "FullyQualifiedName~UnitTests"
  --test-adapter-path "."
  --logger "xunit;LogFilePath=TodoWebApp.UnitTests.xunit.xml"
  /p:CollectCoverage=True
  /p:CoverletOutputFormat=opencover
  /p:CoverletOutput="TodoWebApp.UnitTests.opencover.xml"
  /p:Include="[TodoWebApp]*"
```

### Run jobs on different operating systems

Azure Pipelines has the ability of running the jobs found in a pipeline on different operating systems in parallel: Linux, macOS and Windows.
Each pipeline job must declare a [pool](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=schema#pool) with one specific virtual machine image; Microsoft provides several images, as documented [here](https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/hosted?view=azure-devops&tabs=yaml#use-a-microsoft-hosted-agent).

Here is a YAML fragment declaring several jobs to be run on the aforementioned operating systems:

```yaml
...
- job: 'build-on-linux'
  displayName: 'Build on Linux'
  pool:
    vmImage: 'ubuntu-16.04'
  ...

- job: 'build-on-mac'
  displayName: 'Build on macOS'
  pool:
    vmImage: 'macOS-10.13'
  ...

- job: 'build-on-windows'
  displayName: 'Build on Windows'
  pool:
    vmImage: 'vs2017-win2016'
  ...
```

### Use templates

Since I'm building a .NET Core application, I would like to ensure it will run on each operating system supported by .NET Core: Linux, macOS and Windows; on the other hand, I would like to avoid creating 3 pipelines with the only difference between them being the virtual machine image they use. The good news is that I can employ the concept of [job template](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=example&viewFallbackFrom=vsts#job-templates), a way of reusing code.  
Instead of having to create and maintain 3 almost identical YAML files (one per pipeline per OS), I'm authoring just 2 files:

- the [pipeline YAML file](https://github.com/satrapu/aspnet-core-logging/blob/master/Build/azure-pipelines.yml), dealing with the repository hosting the application source code, pipeline triggers and variables
- the [job templates YAML file](https://github.com/satrapu/aspnet-core-logging/blob/master/Build/azure-pipelines.job-template.yml), containing the __parameterizable__ reusable code used for building the .NET Core application

The pipeline file references the job templates file(s) which must be located inside the same repository.
The [parameters](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops#passing-parameters) declared by the job templates file can be set to default values, so when the pipeline file includes the job templates one, it doesn't have to provide them all. The parameters are referenced inside the job templates file using a JSON-like notation, as seen in the example below.  
Pipeline file fragment:

```yaml
jobs:
- template: './azure-pipelines.job-template.yml'
  parameters:
    job:
      name: 'linux'
      displayName: 'Build on Linux'
    pool:
      vmImage: 'ubuntu-16.04'
    sonar:
      enabled: False
      buildBreaker:
        enabled: False

- template: './azure-pipelines.job-template.yml'
  parameters:
    job:
      name: 'macOS'
      displayName: 'Build on macOS'
    pool:
      vmImage: 'macOS-10.13'
    sonar:
      enabled: False
      buildBreaker:
        enabled: False

- template: './azure-pipelines.job-template.yml'
  parameters:
    job:
      name: 'windows'
      displayName: 'Build on Windows'
    pool:
      vmImage: 'vs2017-win2016'
```

Job templates file fragment:
{% raw %}

```yaml
parameters:
  job:
    name: ''
    displayName: ''
  pool: ''
  build:
    configuration: 'Release'
  sonar:
    enabled: True
    buildBreaker:
      enabled: True
jobs:
- job: ${{ parameters.job.name }}
  displayName: ${{ parameters.job.displayName }}
  continueOnError: False
  pool: ${{ parameters.pool }}
  workspace:
    clean: all
```

{% endraw %}

The concept of job template is applicable to steps too, as documented [here](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops#step-re-use).

### Use variables and variable groups

A pipeline can declare and reference variables inside the YAML file or by importing external ones; these variables can be associated into groups.  
Variables and variable groups are declared in this way:

```yaml
# Pipeline YAML file
variables:
  - group: 'GlobalVariables'

  - group: 'SonarQube'

  - name: 'DotNetSkipFirstTimeExperience'
    value: 1

  - name: 'DotNetCliTelemetryOptOut'
    value: 1

  - name: 'CoreHostTrace'
    value: 0
```

And are referenced like this:

```yaml
# Job templates YAML file
# The "env" property denotes the environment variables passed
# to the "dotnet build" command
- script: >-
    dotnet build $(Build.SourcesDirectory)/Todo.sln
    --configuration ${{ parameters.build.configuration }}
  name: 'build_sources'
  displayName: 'Build sources'
  enabled: True
  env:
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE: $(DotNetSkipFirstTimeExperience)
    DOTNET_CLI_TELEMETRY_OPTOUT: $(DotNetCliTelemetryOptOut)
    COREHOST_TRACE: $(CoreHostTrace)
```

The variable groups are declared outside the YAML files; follow [these steps](https://docs.microsoft.com/en-us/azure/devops/pipelines/library/variable-groups?view=azure-devops&tabs=yaml) to add a new group.  
In order to use this variable group in your pipeline, you have to link it:

- Go to Azure DevOps project home page (e.g. [https://dev.azure.com/satrapu/aspnet-core-logging](https://dev.azure.com/satrapu/aspnet-core-logging))
- Click __Pipelines__ menu item from the left side
- Click __Builds__ menu item under __Pipelines__
- Select the appropriate pipeline and click the top right __Edit__ button
- Inside the pipeline editor, click the __...__ button and then __Pipeline settings__ button
- Go to __Variables__ tab and click __Link variable groups__ button
- Choose the appropriate group and click __Link__ button

Once the variable groups has been linked to your pipeline and declared inside the pipeline YAML file, use its variables like the ordinary ones.  

### Use secrets

A variable group may contain variables marked as secret (click the lock icon on the right side of the appropriate variable editor found under Pipelines -> Library -> Variable Groups menu).  
These variables may contain sensitive data like passwords, tokens, etc.; they may also be mapped to secrets stored in Azure KeyVault, as documented [here](https://docs.microsoft.com/en-us/azure/devops/pipelines/library/variable-groups?view=azure-devops&tabs=yaml#link-secrets-from-an-azure-key-vault).  

The pipeline presented in this article uses a variable marked as secret for storing the [token](#use-sonarcloud-token-during-build) used for authenticating against the SonarCloud project.

## Build application

Building this .NET Core application means compiling its source code, running automated tests with code coverage, publishing test results and code coverage report, performing and then publishing the results of the static code analysis and finally (and debatably) checking whether the quality gate has been passed or not.  

### Install .NET Core SDK

It's always a good idea to use the same tools on both your development machine and the CI server to avoid the "Works on my machine!" syndrome, so installing the same version of the .NET Core SDK is a good start. Azure Pipelines provides a task for this purpose - check its documentation [here](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/tool/dotnet-core-tool-installer?view=azure-devops).  
The example below installs version __[2.2.101](https://github.com/dotnet/core/blob/master/release-notes/2.2/2.2.101-SDK/2.2.101.md)__:

```yaml
variables:
  - name: 'DotNetCore_SDK_Version'
    value: '2.2.101'
...
- task: DotNetCoreInstaller@0
  name: install_dotnetcore_sdk
  displayName: Install .NET Core SDK
  enabled: True
  inputs:
    packageType: 'sdk'
    version: $(DotNetCore_SDK_Version)
```

An additional reason for installing a particular .NET Core SDK version is fixing an issue occurring when trying to install a .NET Core tool, like ReportGenerator - see more details [here](https://github.com/Microsoft/azure-pipelines-tasks/issues/8291).

### Compile source code

Compiling .NET Core source code is done using the [dotnet build](https://docs.microsoft.com/en-us/dotnet/core/tools/dotnet-build?tabs=netcore2x) command invoked from a [cross-platform script](https://docs.microsoft.com/en-us/azure/devops/pipelines/scripts/cross-platform-scripting?view=azure-devops&tabs=yaml) task:
{% raw %}

```yaml
- script: >-
    dotnet build $(Build.SourcesDirectory)/Todo.sln
    --configuration ${{ parameters.build.configuration }}
  name: 'build_sources'
  displayName: 'Build sources'
  enabled: True
```

{% endraw %}

Please note the parameter reference above, __{% raw %}${{ parameters.build.configuration }}{% endraw %}__ - I could've used __Release__ value instead, but it's always a good idea to use parameters instead of hard-coded values.

## Run automated tests

Running unit and integration tests on each commit is __crucial__ as this is one of the most important ways of spotting bugs way before reaching production.  
I have used [xUnit.net framework](https://xunit.github.io/) for writing these tests, but at the moment, my application uses the [in-memory Entity Framework Core provider](https://docs.microsoft.com/en-us/ef/core/providers/in-memory/), so the integration tests are kind of lame; on the other hand, this is a good reason to explore in the near future how Azure Pipelines can be used to start a relational database to be targeted by the integration tests and then blog about it.  

Azure Pipelines provides the [VSTest@2 task](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/test/vstest?view=azure-devops) for running tests, but since I have encountered several issues using it and since I also wanted more control over this operation, I have decided to use the aforementioned [cross-platform script](https://docs.microsoft.com/en-us/azure/devops/pipelines/scripts/cross-platform-scripting?view=azure-devops&tabs=yaml) task for calling the [dotnet test](https://docs.microsoft.com/en-us/dotnet/core/tools/dotnet-test?tabs=netcore21) command.  

### Setup test logger

Azure Pipelines displays test results generated by various frameworks (e.g.: NUnit, xUnit, etc.) in a dedicated tab. The __dotnet test__ command can be configured to generate such results via the __--logger__ parameter. Since my tests have been written using xUnit.net framework, I have used [xUnit Test Logger](https://github.com/spekt/xunit.testlogger) by adding a reference to the appropriate [NuGet package](https://www.nuget.org/packages/XunitXml.TestLogger/).

### Run unit tests

The unit tests related classes reside in a separate folder, [Tests/UnitTests](https://github.com/satrapu/aspnet-core-logging/tree/master/Tests/UnitTests), so when using the *dotnet test* command, I need to specify a [filter](https://docs.microsoft.com/en-us/dotnet/core/testing/selective-unit-tests#xunit) to ensure only this kind of tests are run.  
The command contains other parameters as well, since I'm also collecting code coverage data.

{% raw %}

```yaml
- script: >-
    dotnet test $(Build.SourcesDirectory)/Todo.sln
    --no-build
    --configuration ${{ parameters.build.configuration }}
    --filter "FullyQualifiedName~UnitTests"
    --test-adapter-path "."
    --logger "xunit;LogFilePath=TodoWebApp.UnitTests.xunit.xml"
    /p:CollectCoverage=True
    /p:CoverletOutputFormat=opencover
    /p:CoverletOutput="TodoWebApp.UnitTests.opencover.xml"
    /p:Include="[TodoWebApp]*"
  name: run_unit_tests
  displayName: Run unit tests
  enabled: True
```

{% endraw %}

The __--logger__ parameter specifies that the test results files will be generated using xUnit format; the __LogFilePath__ property specifies the name of the test results file, name which will be used when publishing these results. Each solution project located under the UnitTests folder will generate a test results file named __TodoWebApp.UnitTests.xunit.xml__.

### Run integration tests

Running the integration tests residing inside the [Tests/IntegrationTests](https://github.com/satrapu/aspnet-core-logging/tree/master/Tests/IntegrationTests) folder is done in a similar way, the only differences being the filter and the result file names:

{% raw %}

```yaml
- script: >-
    dotnet test $(Build.SourcesDirectory)/Todo.sln
    --no-build
    --configuration ${{ parameters.build.configuration }}
    --filter "FullyQualifiedName~IntegrationTests"
    --test-adapter-path "."
    --logger "xunit;LogFilePath=TodoWebApp.IntegrationTests.xunit.xml"
    /p:CollectCoverage=True
    /p:CoverletOutputFormat=opencover
    /p:CoverletOutput="TodoWebApp.IntegrationTests.opencover.xml"
    /p:Include="[TodoWebApp]*"
  name: run_integration_tests
  displayName: Run integration tests
  enabled: True
```

{% endraw %}

### Publish test results

Once the tests have been run, the pipeline publishes their results via the [PublishTestResults@2 task](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/test/publish-test-results?view=azure-devops&tabs=yaml):

{% raw %}

```yaml
- task: PublishTestResults@2
  displayName: Publish test results
  name: publish_test_results
  enabled: True
  inputs:
    testResultsFormat: 'xUnit'
    testResultsFiles: '$(Build.SourcesDirectory)/Tests/**/*.xunit.xml'
    mergeTestResults: True
    buildConfiguration: ${{ parameters.build.configuration }}
    publishRunAttachments: True
```

{% endraw %}

Both unit and integration test results files are located under the __Tests__ folder and their names end in __.xunit.xml__, thus the need to set the __testResultsFiles__ YAML property to the above expression.

## Code coverage using Coverlet

Last year I have read [an article](https://www.hanselman.com/blog/NETCoreCodeCoverageAsAGlobalToolWithCoverlet.aspx) by Scott Hanselman about code coverage using [Coverlet](https://github.com/tonerdo/coverlet) and this really got under my skin, so I *had* to use this tool in my next .NET Core project!  

Before describing how Coverlet can be integrated with Azure Pipelines, I have to say this: code coverage should __not__ be used as a quality metric in a project, since reaching a high percentage of coverage does not necessarily mean your code is bug free; on the other hand, coverage can help you in identifying those parts of your application which are __not__ tested.

Coverlet [GitHub project page](https://github.com/tonerdo/coverlet#usage) states that:
> Coverlet can be used either as a .NET Core global tool that can be invoked from a terminal or as a NuGet package that integrates with the MSBuild system of your test project.

Considering the above statement, I have chosen to [integrate Coverlet with MSBuild](https://github.com/tonerdo/coverlet#msbuild) by adding a reference to the [coverlet.msbuild](https://www.nuget.org/packages/coverlet.msbuild/) NuGet package and set specific MSBuild properties to the appropriate values when running [unit](#run-unit-tests) and [integration](#run-integration-tests) tests,.

### Collect code coverage data

In order to collect code coverage, one must use several MSBuild properties:

- [CollectCoverage](https://github.com/tonerdo/coverlet#code-coverage-1) - used for enabling or disabling collecting coverage data
- [CoverletOutputFormat](https://github.com/tonerdo/coverlet#coverage-output-1) - used for specifying the format of the coverage data (e.g. OpenCover, Cobertura, etc.)
- CoverletOutput - used for specifying the path where the coverage data file will be generated
- [Include](https://github.com/tonerdo/coverlet#filters-1) - used for specifying for which assemblies and classes to collect coverage data
- Many others

I have chosen OpenCover as the coverage data format since it's [supported by SonarQube](https://docs.sonarqube.org/pages/viewpage.action?pageId=6389770), a code quality tool also used by my pipeline:

```yaml
- script: >-
    dotnet test $(Build.SourcesDirectory)/Todo.sln
    ...
    /p:CollectCoverage=True
    /p:CoverletOutputFormat=opencover
    /p:CoverletOutput="TodoWebApp.UnitTests.opencover.xml"
    /p:Include="[TodoWebApp]*"
```

### Install ReportGenerator .NET Core tool

Azure Pipelines provides a task for publishing code coverage, [PublishCodeCoverageResults@1](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/test/publish-code-coverage-results?view=azure-devops), but since this task only supports coverage data files in Cobertura or JaCoco formats, I had to use [ReportGenerator](https://github.com/danielpalme/ReportGenerator) for converting files from OpenCover format to Cobertura. This tool can be installed as a [.NET Core global tool](https://docs.microsoft.com/en-us/dotnet/core/tools/global-tools), so it was easy to integrate it with my pipeline:

{% raw %}

```yaml
variables:
  - name: 'ReportGenerator_Version'
    value: '4.0.7'
...
- script: >-
    dotnet tool install dotnet-reportgenerator-globaltool
    --global
    --version $(ReportGenerator_Version)
  name: install_code_coverage_report_generator
  displayName: Install code coverage report generator tool
  enabled: True
```

{% endraw %}

### Generate code coverage HTML report using ReportGenerator

ReportGenerator is capable of converting coverage data files in OpenCover format into several formats, all at once:

- Cobertura: used for calculating coverage metrics
- HTML optimized for Azure Pipelines: used for displaying coverage results as HTML

Once ReportGenerator has been installed as a .NET Core global tool, it can be invoked from command line like this:

```yaml
- script: >-
    reportgenerator
    "-reports:$(Build.SourcesDirectory)/Tests/**/*.opencover.xml"
    "-targetdir:$(Build.SourcesDirectory)/.CoverageResults/Report"
    "-reporttypes:Cobertura;HtmlInline_AzurePipelines"
  name: generate_code_coverage_report
  displayName: Generate code coverage report
  enabled: True
```

The tools will scan all test projects for coverage data files in OpenCover format and will generate both Cobertura and HTML files, the output folder being __.CoverageResults/Report__.  
This folder contains a Cobertura.xml file storing all coverage metrics, and several HTML files containing the source code with coverage related highlighted lines:

```bash
│   Cobertura.xml
│   index.htm
│   index.html
│   TodoWebApp_LoggingMiddleware.htm
│   TodoWebApp_LoggingMiddlewareExtensions.htm
│   TodoWebApp_LoggingService.htm
│   TodoWebApp_Program.htm
│   TodoWebApp_Startup.htm
│   TodoWebApp_StreamExtensions.htm
│   TodoWebApp_TodoController.htm
│   TodoWebApp_TodoDbContext.htm
│   TodoWebApp_TodoItem.htm
│   TodoWebApp_TodoService.htm
│
└───summary236
        Cobertura.xml
```

Click [here](https://satrapu.visualstudio.com/2407d56f-dabc-4301-8ac1-cab15e9e9b20/_apis/build/builds/236/artifacts?artifactName=Code%20Coverage%20Report_236&api-version=5.1-preview.5&%24format=zip) to download a sample.

### Publish code coverage report

Once the code coverage report has been generated, the pipeline will use the [PublishCodeCoverageResults@1 task](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/test/publish-code-coverage-results?view=azure-devops) to publish it:

```yaml
- task: PublishCodeCoverageResults@1
  name: publish_code_coverage_report
  displayName: Publish code coverage report
  enabled: True
  inputs:
    codeCoverageTool: 'Cobertura'
    summaryFileLocation: '$(Build.SourcesDirectory)/.CoverageResults/Report/Cobertura.xml'
    reportDirectory: '$(Build.SourcesDirectory)/.CoverageResults/Report'
```

## Static code analysis using SonarQube

[SonarQube](https://www.sonarqube.org/) is a product developed by [SonarSource](https://www.sonarsource.com/) which helps developers write higher quality code. This tool supports many programming languages, C# being one of them. SonarQube can be deployed on premise, but it can also be used as a service and since my pipeline runs on Azure, I have used the latter model.  

Doing static code analysis against a .NET Core solution usually consists of:

- Installing a specific .NET Core tool which performs the static analysis
- Begin the analysis
- Build the solution
- Run automated tests with code coverage
- Upload the analysis results to SonarCloud
- Check quality gate

### SonarCloud

[SonarCloud](https://sonarcloud.io/about) is *SonarQube as a Service* and it's [free](https://sonarcloud.io/about/pricing) for open source projects, like [mine](https://github.com/satrapu/aspnet-core-logging).  
Any SonarCloud project comes with a predefined quality gate which is read-only, but you can use it as a template to create your own, as documented [here](https://sonarcloud.io/documentation/user-guide/quality-gates/).  
SonarCloud is an active product, so expect features to pop on almost weekly basis, like this one: [Pull Requests get a real Quality Gate status](https://community.sonarsource.com/t/pull-requests-get-a-real-quality-gate-status/7814).

### Setup SonarCloud account

Creating an account is simple as navigating to SonarCloud [home page](https://sonarcloud.io/sessions/new) and pick your login account type - in my case this is GitHub.  

### Use SonarCloud token during build

In order to have SonarCloud analyze the code quality report generated by the pipeline, one has to provide a token which acts as a username and password - follow [these steps](https://docs.sonarqube.org/latest/user-guide/user-token/) to create a token.  
Treat this token as you would a password, so don't share it, nor store it as plain text in your source code. The pipeline will use it via Azure Pipelines support for [secrets](#use-secrets):

{% raw %}

```yaml
- script: >-
    dotnet-sonarscanner ...
    /d:sonar.login="$(CurrentProject.Sonar.Token)"
    ...
  name: prepare_sonarqube_analysis
  displayName: Prepare SonarQube analysis
  enabled: ${{ parameters.sonar.enabled }}
```

{% endraw %}

The __/d:sonar.login="$(CurrentProject.Sonar.Token)"__ parameter instructs the static code analyzer to use the token passed as a variable reference.

### Install dotnet-sonarscanner tool

[This page](https://docs.sonarqube.org/display/SCAN/Analyzing+with+SonarQube+Scanner+for+MSBuild) states:
> The SonarScanner for MSBuild is the recommended way to launch a SonarQube or SonarCloud analysis for projects/solutions using MSBuild or dotnet command as build tool.

In other words, there is a .NET Core tool, [dotnet-sonarscanner](https://www.nuget.org/packages/dotnet-sonarscanner), which can be used for doing static code analysis from within a pipeline:

{% raw %}

```yaml
variables:
  - name: 'SonarScanner_Version'
    value: '4.5.0'
...
- script: >-
    dotnet tool install dotnet-sonarscanner
    --global
    --version $(SonarScanner_Version)
  name: install_sonarscanner
  displayName: Install SonarQube static code analyzing CLI tool
  enabled: ${{ parameters.sonar.enabled }}
```

{% endraw %}

### Run dotnet-sonarscanner tool

The static code analysis must be initiated via the __begin__ verb of the dotnet-sonarscanner tool:

{% raw %}

```yaml
- script: >-
    dotnet-sonarscanner begin
    /k:"$(CurrentProject.Sonar.ProjectKey)"
    /v:"$(CurrentProject.Version)"
    /s:"$(Build.SourcesDirectory)/Build/SonarQubeAnalysis.xml"
    /d:sonar.login="$(CurrentProject.Sonar.Token)"
    /d:sonar.branch.name="$(Build.SourceBranchName)"
  name: prepare_sonarqube_analysis
  displayName: Prepare SonarQube analysis
  enabled: ${{ parameters.sonar.enabled }}
```

{% endraw %}

The command above uses several parameters:

- __/k:"$(CurrentProject.Sonar.ProjectKey)"__ specifies the key of the project currently being analyzed
  - The project key is represented by the value of the __id__ query string parameter present on the [SonarCloud projects page](https://sonarcloud.io/projects)
  - For [my project](https://sonarcloud.io/dashboard?id=aspnet-core-logging), the project key is __aspnet-core-logging__
- __/v:"$(CurrentProject.Version)"__ specifies the version to be associated with the current analysis
  - This means you can track the quality history of your project over a period of time; visit this history on the SonarCloud [activity page](https://sonarcloud.io/project/activity?id=aspnet-core-logging)
- __/s:"$(Build.SourcesDirectory)/Build/SonarQubeAnalysis.xml"__ specifies the XML settings file used to customize the current analysis
  - See the settings applicable to my project [here](https://github.com/satrapu/aspnet-core-logging/blob/master/Build/SonarQubeAnalysis.xml)
  - Most analysis parameters can be found [here](https://docs.sonarqube.org/latest/analysis/analysis-parameters/)
- __/d:sonar.login="$(CurrentProject.Sonar.Token)"__ represents the authentication token
- __/d:sonar.branch.name="$(Build.SourceBranchName)"__ represents the source control branch containing the code currently being analyzed
  - __$(Build.SourceBranchName)__ is an Azure Pipeline built-in variable

### Upload static code analysis report

Once the analysis has been done, the local data collected during this operation must be uploaded to the cloud using the __end__ verb of the dotnet-sonarscanner tool:

{% raw %}

```yaml
- script: >-
    dotnet-sonarscanner end  
    /d:sonar.login="$(CurrentProject.Sonar.Token)"
  name: upload_sonarqube_report
  displayName: Upload SonarQube report
  enabled: ${{ parameters.sonar.enabled }}
```

{% endraw %}

Only the __token__ must be specified at this point.  

Since the pipeline is run on several operating systems, I have disabled Sonar analysis on both Linux and macOS, so the report to be uploaded will contain data collected on Windows only. As a direct consequence, the build running on Windows will take significantly more time when compared to the builds running on Linux and macOS.

### Use SonarLint

What if you'd like to know whether your changes will pass the quality gate *before* committing them? Welcome, [SonarLint](https://www.sonarlint.org/)! This __free__ tool is installed in your favorite IDE and can be connected to your SonarCloud project. For instance, check [this page](https://www.sonarlint.org/visualstudio/) for the steps needed to integrate SonarLint with Visual Studio.

### Use SonarQube build breaker

By *build breaker* I mean the ability of failing the pipeline in case the SonarQube quality gate did not pass due to some issues like duplicated code or a security flaw. Such feature looks very appealing, but it seems there is a catch: starting with [version 5.2](https://blog.sonarsource.com/sonarqube-5-2-in-screenshots/), SonarQube asynchronously analyzes the report it receives from a scanner. Such analysis can take a while, so if a build polls SonarQube server for the results, some resources may be blocked (e.g. the machine running the build), as stated [here](https://blog.sonarsource.com/breaking-the-sonarqube-analysis-with-jenkins-pipelines/).  

Anyway, for the sake of experimenting and out of curiosity, I have investigated how can I implement such build breaker and I've stumbled upon a [PowerShell script](https://github.com/michaelcostabr/SonarQubeBuildBreaker/blob/master/SonarQubeBuildBreaker.ps1) and after some tweaking, [I was able](https://github.com/satrapu/aspnet-core-logging/blob/master/Build/SonarBuildBreaker.ps1) to query the SonarCloud server for the status of the quality gate and break the build if the gate did not pass:

{% raw %}

```yaml
- task: PowerShell@2
  name: sonar_build_breaker
  displayName: Run Sonar build breaker
  condition: |
    and
    (
      eq( ${{ parameters.sonar.enabled }}, True),
      eq( ${{ parameters.sonar.buildBreaker.enabled }}, True)
    )
  inputs:
    targetType: 'filePath'
    filePath: '$(Build.SourcesDirectory)/Build/SonarBuildBreaker.ps1'
    arguments: >-
      -SonarToken "$(CurrentProject.Sonar.Token)"
      -DotSonarQubeFolder "$(Agent.BuildDirectory)/.sonarqube"
    errorActionPreference: stop
    failOnStderr: True
    workingDirectory: $(Build.SourcesDirectory)
```

{% endraw %}

The task above, [PowerShell@2](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/utility/powershell?view=azure-devops), queries the SonarCloud server only if both the SonarQube analysis and build breaker are enabled; for this purpose, I had to resort to custom expressions, like the ones documented [here](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/conditions?view=azure-devops&tabs=yaml#examples).  

Feel free to disable this task if you're not OK with this build breaker!

## Badges

### Azure Pipeline status badge

Follow [these steps](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started-yaml?view=azure-devops#get-the-status-badge) to display a build status badge on your GitHub README.md file.

### Sonar quality gate badge

In order to display the quality gate badge on your GitHub README.md file, go to your SonarCloud project dashboard (e.g. [https://sonarcloud.io/dashboard?id=aspnet-core-logging](https://sonarcloud.io/dashboard?id=aspnet-core-logging)) and click the __Get project badges__ button from bottom right and choose one of the many available badges; the *quality gate* Markdown fragment looks like this:

```markdown
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=aspnet-core-logging&metric=alert_status)](https://sonarcloud.io/dashboard?id=aspnet-core-logging)
```

## Conclusion

Setting up my first instance of Azure Pipelines was not easy, but now that I've reached the point where each of my code changes triggers an automated build, I know there are so many ways to extend it:

- Use Docker for running a database to be targeted by some real integration tests
- Run a code quality tool like [InspectCode](https://www.jetbrains.com/help/resharper/InspectCode.html)
- Run a security scanner like [Snyk](https://snyk.io/)
- Run a license management tool like [Whitesource](https://www.whitesourcesoftware.com/)
- Integrate many other tools to ensure my OSS code is top of the line

Azure Pipelines is not the only way of achieving CI for your OSS project, [AppVeyor](https://www.appveyor.com/) being one of the alternatives, but having the ability of building my code against all major operating systems, having access to [so many features](https://azure.microsoft.com/en-us/services/devops/pipelines/), it's really nice, so most definitely I will invest more in learning and experimenting with Azure Pipelines!

## References

- [Azure DevOps](https://azure.microsoft.com/en-us/services/devops/)
  - [Documentation](https://docs.microsoft.com/en-us/azure/devops/?view=azure-devops)
  - [Pricing for Azure DevOps](https://azure.microsoft.com/en-us/pricing/details/devops/azure-pipelines/), including a free plan
- [Azure Pipelines](https://azure.microsoft.com/en-us/services/devops/pipelines/)
  - [Documentation](https://docs.microsoft.com/en-us/azure/devops/pipelines/index?view=azure-devops)
  - [YAML schema reference](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=schema)
  - Other people's pipelines
    - [BenchmarkDotNet](https://github.com/dotnet/BenchmarkDotNet/blob/master/azure-pipelines.Windows.yml)
    - [Roslyn](https://github.com/dotnet/roslyn/blob/master/azure-pipelines.yml)
    - [ReportGenerator](https://github.com/danielpalme/ReportGenerator/blob/master/azure-pipelines.yml)
- [Azure DevOps Extensions](https://marketplace.visualstudio.com/azuredevops/)
  - [Azure Pipelines for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=ms-azure-devops.azure-pipelines)
- [SonarSource](https://www.sonarsource.com/)
  - [Plans & Pricing](https://www.sonarsource.com/plans-and-pricing/)
  - [SonarCloud Documentation](https://sonarcloud.io/documentation/)
