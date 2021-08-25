---
layout: post
title: "Structured logging in ASP.NET Core using Serilog and Seq"
date: 2021-08-16 22:40:07 +0200
tags: [programming, dotnet, dotnet-core, aspnet-core, logging, structured-logging, serilog, seq]
---

- [Context](#context)
- [What is unstructured logging?](#unstructured-logging)
- [What is structured logging?](#structured-logging)
- [What is Serilog?](#what-is-serilog)
  - [Serilog sinks](#serilog-sinks)
  - [Serilog enrichers](#serilog-enrichers)
  - [Serilog properties](#serilog-properties)
  - [Serilog destructuring](#serilog-destructuring)
    - [Using destructuring operator](#destructuring-operator)
    - [Using destructuring policies](#destructuring-policies)
    - [Using destructuring libraries](#destructuring-libraries)
  - [Configure Serilog](#configure-serilog)
    - [Configure Serilog nouns](#configure-serilog-nouns)
    - [Configure Serilog as an ASP.NET Core logging provider](#configure-serilog-as-logging-provider)
- [What is Seq?](#what-is-seq)
  - [Run Seq using Docker](#run-seq-using-docker)
  - [Crash course for querying Seq data](#query-seq-data)
- [Log application events](#log-application-events)
  - [Use message templates](#use-message-templates)
  - [Use log scopes](#use-log-scopes)
- [Use cases](#use-cases)
  - [Debugging](#debugging-use-case)
    - [Identify error root cause](#identify-error-root-cause)
    - [Fetch events from same conversation](#fetch-conversation-events)
  - [Analytics](#analytics-use-case)
    - [Identify most used application features](#identify-most-used-application-features)
  - [Auditing](#auditing-use-case)
    - [Audit user actions](#audit-user-actions)
  - [Performance](#performance-use-case)
    - [Identify slowest SQL queries](#identify-slowest-sql-queries)
    - [Identify slowest application features](#identify-slowest-application-features)
- [References](#references)
- [Conclusion](#conclusion)

* * *
<!-- markdownlint-disable MD033 -->
<h2 id="context">Context</h2>

Back in 2016 I was part of a team developing an e-care web application using SAP Hybris platform for an European telco. Among many other things, I was tasked with the initial deployment to the UAT environment which was supposed to be promoted to production as soon as the client would have validated that particular release. The web application was running in a Tomcat cluster made out of 8 or 9 Linux servers which I was able to access via SSH only, thus in order to investigate any issue occurring on that particular environment, I had to use CLI and run specific Linux commands in order to search for relevant lines of text found inside application log files - if I remember correctly, we were using [less](https://man7.org/linux/man-pages/man1/less.1.html) command.  
One of my colleagues had a [MacBook Pro](https://www.apple.com/macbook-pro/) and with the help of [iterm2](https://iterm2.com/) he was able to split his window into one pane per server and run each command against all of them; unfortunately for me, at that time I was using a laptop running Windows, so I had to open one console per server and run each command inside each console which was a very time consuming and error prone activity.  
There were two particular issues with this approach (beside lack of productivity due to dealing with multiple consoles): any real-time investigation was limited by Linux CLI support for searching text files and when any more offline advanced investigation was needed, we had to ask the client IT department to send us specific log files and use a text editor like [Notepad++](https://notepad-plus-plus.org/) to search across several files. These issues are direct consequences of employing [unstructured logging](#unstructured-logging) when dealing with application events.

The purpose of this post is to present a way to create and query application events using the [structured logging](#structured-logging) mechanism provided by ASP.NET Core, with the help of [Serilog](https://serilog.net/) and [Seq](https://datalust.co/seq).

All code fragments found in this post are part of my pet project [aspnet-core-logging](https://github.com/satrapu/aspnet-core-logging); furthermore, I have created a [tag](https://github.com/satrapu/aspnet-core-logging/tree/v20210824) to ensure these fragments will remain the same, no matter how this project will evolve.

<h2 id="unstructured-logging">What is unstructured logging?</h2>

Creating an application event is usually done by instantiating a string, maybe using [string interpolation](https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/tokens/interpolated) and then sending it to a console, file or database using a logging library like [Log4Net](https://logging.apache.org/log4net/); an educated developer might even check whether the logging library will log the event before creating it to avoid waisting time and resources - see more details about such approach inside the __Performance__ section of the article found [here](https://logging.apache.org/log4net/release/manual/internals.html#performance).  
This approach is called __logging__, since we keep a __log__ of events. As the events have been created using plain text, when we need to search for specific data inside the log, we usually resort to the basic search feature offered by the text editor at hand or maybe regular expressions. Neither approach is suitable for complex searches - a text editor can only search for words contained inside the events stored in one or more files, while writing a custom regex to fetch specific data is not an easy task, plus searching through *all* events means you need to access *all* log files, a feat which might involve terrabytes of data or even more; also, how do you write a regex to fetch the answer to a question like: *What events created during this specific time period contain (or do not contain) this particular pieces of information*?  
This is __unstructured logging__, since an event is just a line of text which does not have any structure.  

<h2 id="structured-logging">What is structured logging?</h2>

__Structured logging__ means creating events having a particular __structure__; such data can then be ingested by another service which offers the means to parse, index and finally query it.  
ASP.NET Core was built having structure logging in mind with the help of [logging providers](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/logging/?view=aspnetcore-5.0#logging-providers), [message templates](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/logging/?view=aspnetcore-5.0#log-message-template) and [log scopes](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/logging/?view=aspnetcore-5.0#log-scopes).

The [following answer](https://softwareengineering.stackexchange.com/a/312586) best describes the differences between these two logging approaches. Furthermore, this answer was provided by __Nicholas Blumhardt__, who created Serilog - I highly recommend following his [blog](https://nblumhardt.com/) to discover lots and lots of very interesting stuff related to logging in .NET!

<h2 id="what-is-serilog">What is Serilog?</h2>

ASP.NET Core provides several [built-in logging providers](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/logging/?view=aspnetcore-5.0#built-in-logging-providers) and when I have initially started using this framework, as I was already familiar with Log4Net, I employed the [Microsoft.Extensions.Logging.Log4Net.AspNetCore](https://www.nuget.org/packages/Microsoft.Extensions.Logging.Log4Net.AspNetCore/) NuGet package - that was mid 2018. Several months later, I stumbled upon [Serilog](https://serilog.net/) and [Seq](https://datalust.co/seq) and I was blown away by this very powerful combination.  

__Serilog__ is a logging framework *with powerful structured event data in mind* (as stated on its [home page](https://serilog.net/)) which was initially released as a [NuGet package](https://www.nuget.org/packages/Serilog/) in 2013. One uses Serilog to create events having a given structure and stores them in specific place, like a file or database. Serilog uses several *nouns*, like: [sinks](#serilog-sinks), [enrichers](#serilog-enrichers), [properties](#serilog-properties) and [destructuring policies](#serilog-destructuring) and others, at the same time offering the means to configure its behavior either via code-based or file-based [configuration sources](#configure-serilog).  
The community around this library is pretty solid, as seen on [NuGet gallery](https://www.nuget.org/packages?q=Tags%3A%22serilog%22%22), so one more reason to make Serilog my logging framework of choice!

<h3 id="serilog-sinks">Serilog sinks</h3>

A Serilog sink is a component which receives events generated via Serilog and stores them or sends them over to other components which will further process these events. There are plenty of such sinks, ready to support almost any given scenario - see the official list [here](https://github.com/serilog/serilog/wiki/Provided-Sinks). If this list does not cover *your* scenario, you can always write your own sink by starting from an already implemented one or from [scratch](https://github.com/serilog/serilog/wiki/Developing-a-sink)! Of course, there are many more sinks, as one can see by [querying GitHub](https://github.com/search?l=C%23&q=serilog+sink&type=Repositories).

In 2019 I joined a team developing a deal advisory management application running in Azure where we had 3 web APIs, each one writing events during local development to its own file. Each developer had to search through several files in order to investigate a particular issue or to find a relevant piece of information, a thing which was neither comfortable, nor quick.  
After discovering Seq, I'm now strongly recommending using it for __local development__ via [Serilog.Sinks.Seq](https://github.com/serilog/serilog-sinks-seq) - this enables sending events from the application to a running Seq instance (most likely [a Docker container](#run-seq-using-docker) running on local machine) which will ingest them and then provide the means to perform rather complex queries against *all* events, thus avoiding the overhead and performance penalty caused by logging to files.  
I've also configured the [Serilog.Sinks.Console](https://github.com/serilog/serilog-sinks-console) to quickly allow me spot any errors while performing dev testing locally.  

In case the application production environment (or any remote environment, for that matter) is hosted by a cloud provider, I strongly recommend using the Serilog sink which integrates with the logging/monitoring service of that particular provider - e.g. one could pair [Serilog.Sinks.ApplicationInsights](https://github.com/serilog/serilog-sinks-applicationinsights) with Azure, [Serilog Sink for AWS CloudWatch](https://github.com/Cimpress-MCP/serilog-sinks-awscloudwatch) with AWS and [Serilog.Sinks.GoogleCloudLogging](https://github.com/manigandham/serilog-sinks-googlecloudlogging) with GCP, etc.  
Outside cloud, one could use Seq for all environments, which comes with the benefit of having to learn only one query language instead of two.

Here's a fragment found inside [appsettings.Development.json file](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/appsettings.Development.json#L14-L33) configuring Serilog sinks when application runs locally:

```json
"Serilog": {
  ...
  "Using": [
    "Serilog.Sinks.Console",
    "Serilog.Sinks.Seq"
  ],
  "WriteTo": [
   {
      "Name": "Console",
      "Args": {
        "theme": "Serilog.Sinks.SystemConsole.Themes.AnsiConsoleTheme::Code, Serilog.Sinks.Console",
        "outputTemplate": "{Timestamp:HH:mm:ss.fff} {Level:u3} | cid:{ConversationId} fid:{ApplicationFlowName} tid:{ThreadId} | {SourceContext}{NewLine}{Message:lj}{NewLine}{Exception}"
      }
   },
   {
      "Name": "Seq",
      "Args": {
        "serverUrl": "http://localhost:5341",
        "controlLevelSwitch": "$controlSwitch"
      }
   }
  ],
  ...
```

And here's a fragment found inside [appsettings.DemoInAzure.json file](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/appsettings.DemoInAzure.json#L19-L29) configuring the only Serilog sink used when application runs in Azure:

```json
"Serilog": {
  ...
  "Using": [
    "Serilog.Sinks.ApplicationInsights"
  ],
  "WriteTo": [
   {
      "Name": "ApplicationInsights",
      "Args": {
        "telemetryConverter": "Serilog.Sinks.ApplicationInsights.Sinks.ApplicationInsights.TelemetryConverters.TraceTelemetryConverter, Serilog.Sinks.ApplicationInsights"
      }
   }
  ],
  ...
```

There are several __important things__ worth mentioning:

- We usually need to install one NuGet package per sink, so just declaring them under the `Using` section is not enough
- Each sink has its own list of configuration properties which must be declared under the `Args` section, but usually the GitHub repo of each Serilog sink states how to configure it, so it shouldn't be that hard to properly set it up
  - The `Console` sink uses several placeholders found under its `Args` section:
    - `Timestamp` represents the date and time when the event was created
    - `Level` represents the logging level associated with the event
    - `SourceContext` represents the name of the `logger` used for creating the event; usually it is the name of the class where event was created
    - `NewLine` represents a new line to split event data to several lines
    - `Message` represents the event data
    - `Exception` represents a logged exception (which includes its stack trace)
    - Though not used, there is another very important placeholder, `Properties`, which contains, obviously, all properties associated with the event
  - The `Seq` sink uses `serverUrl` to point to the running Seq instance which will ingest events; my pet project runs Seq via [Docker Compose](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/docker-compose.yml#L73-L87), thus explaining why the host is the local one
- Several sinks might need extra setup outside the application configuration files - e.g. the __instrumentation key__ used by Azure Application Insights is set inside [Startup class](https://github.com/satrapu/aspnet-core-logging/blob/2cec7a7990a9ef2fdf61011baedfeff9d8da21e8/Sources/Todo.WebApi/Startup.cs#L142-L151):

  ```cs
  private void ConfigureApplicationInsights(IServiceCollection services)
  {
      if (IsSerilogApplicationInsightsSinkConfigured)
      {
          var applicationInsightsOptions = new ApplicationInsightsOptions();
          Configuration.Bind(applicationInsightsOptions);

          services.AddApplicationInsightsTelemetry(applicationInsightsOptions.InstrumentationKey);
      }
  }
  ```

<h3 id="serilog-enrichers">Serilog enrichers</h3>

A Serilog enricher is used to add additional properties (*enrichment*) to each event generated via Serilog.  
Check this [wiki page](https://github.com/serilog/serilog/wiki/Enrichment) for more details about pre-built enrichers.  
The community has provided many other enrichers, like: [Serilog.Enrichers.AssemblyName](https://github.com/TinyBlueRobots/Serilog.Enrichers.AssemblyName) (enriches events with assembly related info) or [Serilog.Enrichers.OpenTracing](https://github.com/yesmarket/Serilog.Enrichers.OpenTracing) (enriches events with OpenTracing context). There are many more enrichers, as one can see by [querying GitHub](https://github.com/search?l=C%23&q=serilog+enrich&type=repositories).

My pet project uses [Serilog.Enrichers.Thread](https://github.com/serilog/serilog-enrichers-thread) in order to ensure that the thread ID managed by .NET platform is made available to each application event; this enricher enables better understanding of the application when a particular user action is handled via more than just one thread.  
Here's a fragment found inside [appsettings.json file](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/appsettings.json#L50-L53) configuring Serilog enrichment:

```json
 "Serilog": {
   ...
   "Enrich": [
      "FromLogContext",
      "WithThreadId"
   ],
    ...
 }
```

There are several __important things__ worth mentioning:

- We usually need to install one NuGet package per enricher, so just declaring them under the `Enrich` section is not enough
- Each enricher has its own list of string values which must be declared under the `Enrich` section, but usually the GitHub repo of each Serilog enricher states what they are, so it shouldn't be that hard to properly set it up

<h3 id="serilog-properties">Serilog properties</h3>

Serilog properties are used to provide additional information to each or particular events, thus providing more value to the person querying such data. Each token found in a message template will be made available by Serilog as a property which can be used in a query running inside Seq or any other service capable of handling structured events.

My pet project uses properties to enrich events with information about the name of the application which changes based on the current hosting environment (e.g. local, Azure or anything else) and to provide default values to properties which will be populated at run-time only (e.g. the name of the application flow initiated by a user, the ID of the thread used for running the current code or the ID of the conversation used for grouping related events).  
Here's a fragment found inside [appsettings.json file](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/appsettings.json#L54-L59) configuring Serilog properties when application runs in any environment:

```json
"Serilog": {
  ...
  "Properties": {
    "Application": "Todo.WebApi",
    "ApplicationFlowName": "N/A",
    "ConversationId": "N/A",
    "ThreadId": "N/A"
  },
  ...
}
```

Here's the properties found inside [appsettings.Development.json](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/appsettings.Development.json#L34-L36) used when application runs locally:

```json
"Serilog": {
  ...
  "Properties": {
    "Application": "Todo.WebApi.Development"
  },
  ...
}
```

There are several __important things__ worth mentioning:

- The `N/A` values will be replaced at run-time by actual meaningful values (via [log scopes](#use-log-scopes), as described several sections below, to avoid coupling application code with Serilog API), e.g. `ApplicationFlowName` property will be populated with values like: `TodoItem/Add`, `TodoItems/FetchByQuery` or `Security/GenerateJwt`, based on what user action took place at a particular moment of time
- All of the properties above act as __global__ ones, since they will accompany __any__ event
- Due to the built-in [configuration override mechanism](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/configuration/?view=aspnetcore-5.0#appsettingsjson) provided by ASP.NET Core, when application runs in any environment, each event will be accompanied by `Application`, `ApplicationFlowName`, `ConversationId` and `ThreadId` properties, but the value of the `Application` property will be set to __`Todo.WebApi`__ when application runs in __production__ environment and will be set to __`Todo.WebApi.Development`__ when application runs in __development__ environment.

<h3 id="serilog-destructuring">Serilog destructuring</h3>

Destructuring means extracting pieces of information from an object like a [DTO](https://en.wikipedia.org/wiki/Data_transfer_object ) or [POCO](https://en.wikipedia.org/wiki/Plain_old_CLR_object) and create properties with values.

<h4 id="destructuring-operator">Using destructuring operator</h4>

Serilog offers the [@ destructuring operator](https://github.com/serilog/serilog/wiki/Structured-Data#preserving-object-structure).  
For instance, my pet project uses this operator in order to log the search criteria used for fetching a list of records from a PostgreSQL database via an Entity Framework Core query.  
Here's a fragment found inside [TodoService class](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.Services/TodoItemLifecycleManagement/TodoItemService.cs#L80-L104):

```cs
...
private async Task<IList<TodoItemInfo>> InternalGetByQueryAsync(TodoItemQuery todoItemQuery)
{
    logger.LogInformation("About to fetch items using query {@TodoItemQuery} ...", todoItemQuery);
    ...
}
...
```

<h4 id="destructuring-policies">Using destructuring policies</h4>

In case there is a need to customize the way events are serialized, one can define several [destructuring policies](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/appsettings.json#L60-L86), like this:

```json
...
"Destructure": [
  {
    "Name": "With",
    "Args": {
      "policy": "Todo.Integrations.Serilog.Destructuring.DeleteTodoItemInfoDestructuringPolicy, Todo.Integrations.Serilog"
    }
  },
  {
    "Name": "With",
    "Args": {
      "policy": "Todo.Integrations.Serilog.Destructuring.NewTodoItemInfoDestructuringPolicy, Todo.Integrations.Serilog"
    }
  },
  ...
],
...
```

This is how the [DeleteTodoItemInfoDestructuringPolicy](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.Integrations.Serilog/Destructuring/DeleteTodoItemInfoDestructuringPolicy.cs) class looks like:

```cs
public class DeleteTodoItemInfoDestructuringPolicy : IDestructuringPolicy
{
  public bool TryDestructure(object value, ILogEventPropertyValueFactory propertyValueFactory,
      out LogEventPropertyValue result)
  {
    result = null;
    DeleteTodoItemInfo deleteTodoItemInfo = value as DeleteTodoItemInfo;

    if (deleteTodoItemInfo == null)
    {
        return false;
    }

    result = new StructureValue(new List<LogEventProperty>
    {
        new LogEventProperty(nameof(deleteTodoItemInfo.Id), new ScalarValue(deleteTodoItemInfo.Id)),
        new LogEventProperty(nameof(deleteTodoItemInfo.Owner),
            new ScalarValue(deleteTodoItemInfo.Owner.GetNameOrDefault()))
    });

    return true;
  }
}
```

<h4 id="destructuring-libraries">Using destructuring libraries</h4>

In case destructuring operator and policies are not good enough, one can use libraries provided by community, like:

- [Destructurama.Attributed](https://github.com/destructurama/attributed) which uses attributes to customize event serialization
- [Destructurama.ByIgnoring](https://github.com/destructurama/by-ignoring) which enables excluding individual properties from events (e.g. log an event representing a user, but exclude any sensitive data, like its `Password` property)
- [Destructurama.JsonNet](https://github.com/destructurama/json-net) which enables handling JSON.NET dynamic types as like any other event

<h3 id="configure-serilog">Configure Serilog</h3>

In order for an ASP.NET Core application to use Serilog, several things need to be setup:

- Declare the sinks, enrichers and any other Serilog related nouns used for logging purposes
- Configure application to use Serilog as a logging provider

<h4 id="configure-serilog-nouns">Configure Serilog nouns</h4>

Up until now I have shown the configuration file based way of setting up Serilog, but this library supports code based configuration too. From what I've seen until now, almost each GitHub repo hosting anything related to Serilog (e.g. sink, enricher, etc.), usually documents both approaches. I personally favor setting up Serilog via configuration files since I do not want to redeploy the application each time I need to adjust Serilog setup (i.e. when I need to increase or decrease the current logging level to capture less or more events).

Read more about the different ways of configuring Serilog [here](https://github.com/serilog/serilog/wiki/Configuration-Basics), [here](https://github.com/tsimbalar/serilog-settings-comparison/blob/master/docs/README.md) and [here](https://github.com/serilog/serilog-settings-configuration).  
In case you have to run your application on top of .NET Framework, check [this wiki page](https://github.com/serilog/serilog/wiki/AppSettings) to understand how to configure Serilog via the `appSettings` XML section found inside the application configuration file.

The Serilog JSON configuration of my pet project found inside the appsettings.json can be seen [here](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/appsettings.json#L22-L86); each hosting environment overrides various parts of Serilog configuration, usually the logging level, sinks and global properties, as one can see inside [appsettings.Development.json](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/appsettings.Development.json#L10-L37), [appsettings.IntegrationTests.json](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/appsettings.IntegrationTests.json#L9-L36) and [appsettings.DemoInAzure.json](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/appsettings.DemoInAzure.json#L7-L33) files.

There are several __important things__ worth mentioning:

- The `LevelSwitches` section defines a switch used for controlling the current [logging level](https://github.com/serilog/serilog/wiki/Writing-Log-Events#log-event-levels) used by Serilog - see more details [here](https://github.com/serilog/serilog/wiki/Writing-Log-Events#dynamic-levels)
  - __IMPORTANT:__ This switch can be used for reconfiguring Serilog without the need to restart the application - see more details [here](https://github.com/serilog/serilog-settings-configuration/issues/72)
- The `MinimumLevel` section defines what gets logged and what not - e.g. `{ "Override": { "Microsoft": "Warning"} }` means that from all events generated by classes found under the __Microsoft__ namespace and any of its descendants, Serilog will log only warnings and errors, discarding the rest; `{ "Override": { "Microsoft.EntityFrameworkCore.Database.Command": "Information"} }` means Serilog will log all SQL commands executed by Entity Framework Core
- The `Using` section declares all Serilog sinks to be used by the application
- The `WriteTo` section configures each Serilog sink declared inside the `Using` section
- The `Enrich` section declares all Serilog enrichers to be used by the application
- The `Properties` section declares all Serilog properties which will accompany all application events
- The `Destructure` section declares all Serilog classes used for serializing particular application events

<h4 id="configure-serilog-as-logging-provider">Configure Serilog as an ASP.NET Core logging provider</h4>

Until now I have shown how to configure Serilog nouns, now's the time to show how to add Serilog as a logging provider to an ASP.NET Core application.  
The usual approach is to setup things up in two places:

- [Program class](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/Program.cs), in order to capture any errors occurring during host setup phase
  
  I first need to instantiate Serilog `Logger` class:

  ```cs
  private static readonly Logger logger =
    new LoggerConfiguration()
      .Enrich.FromLogContext()
      .WriteTo.Console()
      .CreateLogger();
  ```

  Then Serilog will be able to log any error:

  ```cs
  public static void Main(string[] args)
  {
      try
      {
          CreateHostBuilder(args).Build().Run();
      }
      catch (Exception exception)
      {
          logger.Fatal(exception, "Todo ASP.NET Core Web API failed to start");
          throw;
      }
      finally
      {
          logger.Dispose();
      }
  }
  ```

- [Startup class](https://github.com/satrapu/aspnet-core-logging/blob/2cec7a7990a9ef2fdf61011baedfeff9d8da21e8/Sources/Todo.WebApi/Startup.cs#L168-L196), in order to let infrastructure know that it can use Serilog as a logging provider:
  
  ```cs
  services.AddLogging(loggingBuilder =>
  {
      if (IsSerilogFileSinkConfigured)
      {
          string logsHomeDirectoryPath = Environment.GetEnvironmentVariable(LogsHomeEnvironmentVariable);

          if (string.IsNullOrWhiteSpace(logsHomeDirectoryPath) || !Directory.Exists(logsHomeDirectoryPath))
          {
              var currentWorkingDirectory = new DirectoryInfo(Directory.GetCurrentDirectory());
              DirectoryInfo logsHomeDirectory = currentWorkingDirectory.CreateSubdirectory("Logs");
              Environment.SetEnvironmentVariable(LogsHomeEnvironmentVariable, logsHomeDirectory.FullName);
          }
      }

      if (!WebHostingEnvironment.IsDevelopment())
      {
          loggingBuilder.ClearProviders();
      }

      loggingBuilder.AddSerilog(new LoggerConfiguration()
          .ReadFrom.Configuration(Configuration)
          .CreateLogger(), dispose: true);
  });
  ```

  There are several __important things__ worth mentioning:

  - In case the current environment has been configured to use `Serilog.Sinks.File` sink, then I will ensure the environment variable `%LOGS_HOME%` [declared](https://github.com/satrapu/aspnet-core-logging/blob/2cec7a7990a9ef2fdf61011baedfeff9d8da21e8/Sources/Todo.WebApi/appsettings.json#L41) under the appropriate `Args` section will be correctly populated at run-time
  - Any built-in logging providers are removed when application runs outside local development environment to minimize the impact logging has over the application performance
  - I'm configuring Serilog via the [current configuration](https://github.com/satrapu/aspnet-core-logging/blob/v20210824/Sources/Todo.WebApi/Program.cs#L51-L60)
  - There is a downside to my current approach, as the Serilog setup found in Program.cs file differs from the one found in Startup.cs file; on the other hand, Nicholas Blumhardt has come up with [a solution](https://nblumhardt.com/2020/10/bootstrap-logger/) and I'm itching for experimenting with it as I'm not happy in having to maintain two Serilog configurations 

<h2 id="what-is-seq">What is Seq?</h2>
Being able to create events with a given structure is not enough when you need to extract relevant data out of them - one needs the means to parse, index and query such data.  
__Seq__ is *machine data, for humans* (as stated on its [home page](https://datalust.co/seq)).

<h3 id="run-seq-using-docker">Run Seq using Docker</h3>

TODO

<h3 id="query-seq-data">Crash course for querying Seq data</h3>

TODO

<h2 id="log-application-events">Log application events</h2>

TODO

<h2 id="use-message-templates">Use message templates</h2>

TODO

<h2 id="use-log-scopes">Use log scopes</h2>

TODO

<h2 id="use-cases">Use cases</h2>

Aggregating application events (and not just application, as one could also collect events generated by the infrastructure used for running this application!) into one place and being able to query them using a structured language is very powerful and can cut costs expressed in reduced investigation time, reduced employee frustration, etc.

<h3 id="debugging-use-case">Debugging</h3>

TODO

<h4 id="identify-error-root-cause">Identify error root cause</h4>

TODO

<h4 id="fetch-conversation-events">Fetch events from same conversation</h4>

TODO

<h3 id="analytics-use-case">Analytics</h3>

TODO

<h4 id="identify-most-used-application-features">Identify most used application features</h4>

TODO

<h3 id="auditing-use-case">Auditing</h3>

TODO

<h4 id="audit-user-actions">Audit user actions</h4>

TODO

<h3 id="performance-use-case">Performance</h3>

TODO

<h4 id="identify-slowest-sql-queries">Identify slowest SQL queries</h4>

TODO

<h4 id="identify-slowest-application-features">Identify slowest application features</h4>

TODO

<h2 id="references">References</h2>

- Serilog
  - Reading
    - [Official Site](https://serilog.net/)
    - [Wiki](https://github.com/serilog/serilog/wiki)
    - [Debugging and Diagnostics](https://github.com/serilog/serilog/wiki/Debugging-and-Diagnostics)
    - [Enrichment](https://github.com/serilog/serilog/wiki/Enrichment)
    - [Formatting Output](https://github.com/serilog/serilog/wiki/Formatting-Output)
    - [Serilog Best Practices by Ben Foster](https://benfoster.io/blog/serilog-best-practices/)
  - Extensions
    - [Serilog Expressions](https://github.com/serilog/serilog-expressions)
      - [Define filter in configuration file](https://stackoverflow.com/a/44035241/5786708)
    - [Serilog.Extensions.Hosting](https://github.com/serilog/serilog-extensions-hosting)
    - Many, many others - just google them
- Seq
  - Reading
    - [Official Site](https://datalust.co/seq)
    - [Official Documentation](https://docs.datalust.co/docs)
    - [Getting Started with Docker](https://docs.datalust.co/docs/getting-started-with-docker)
    - [Structured Logging with Serilog and Seq](https://docs.datalust.co/docs/using-serilog#structured-logging-with-serilog-and-seq)

<h2 id="conclusion">Conclusion</h2>

Structured logging is not just for debugging purposes, as it can be used for various other purposes, like: spotting performance bottlenecks, auditing, analytics, distributed tracing and a lot more.  
Using structured logging is definitely one of the best ways a developer can employ in order to help both business and technical stakeholders make better and more informed decisions to positively impact the outcome of a particular software system.  
The only downside of structured logging I see right now is that you have to learn a new query language for each server you are going to use for ingesting events, so you need to learn one when using Seq and another one when using Azure Application Insights, but I think the price is well worth it due to the amazing amount of information you can extract.

So what are you waiting for? Go put some structure into your events and query them like a boss!
