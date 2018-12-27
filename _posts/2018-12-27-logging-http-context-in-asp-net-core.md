---
layout: post
title: "Logging HTTP context in ASP.NET Core"
date: 2018-12-27 20:15:24 +0200
tags: [programming, dotnet, dotnet-core, aspnet-core, aspnet-core-middleware, log4net, logging]
---

- [Context](#context)
- [Logging support in ASP.NET Core](#logging-in-aspnet-core)
  - [General information](#general-info)
  - [Built-in logging providers](#built-in-logging-providers)
  - [Configure a logging provider](#configure-logging-provider)
  - [Using an ILogger](#using-an-ilogger)
  - [Correlation identifier](#correlation-id)
- [Logging the current HTTP context](#logging-the-current-http-context)
- [Implementation](#implementation)
  - [When to log](#when-to-log)
  - [What to log](#what-to-log) 
  - [How to log](#how-to-log) 
- [Conclusion](#conclusion)

* * * 

<h2 id="context">Context</h2>  
Logging is an important feature each application __must__ have. When deploying a multi-threaded and multi-user application in production, logging becomes __crucial__, as it tends to be the go-to approach for understanding what has happened in case of a production error - I'm not saying this is the *best* way, just the most *common* one I've seen. To have a complete picture over an application running in production, logging should be accompanied by __monitoring__ (e.g. [Prometheus](https://prometheus.io/), etc.) and a __centralized log aggregation solution__ (e.g. [ELK stack](https://www.elastic.co/elk-stack), [EFK stack](https://www.digitalocean.com/community/tutorials/elasticsearch-fluentd-and-kibana-open-source-log-search-and-visualization), etc.).

The purpose of this article is to explain how to log the HTTP requests and responses handled by an ASP.NET Core web application using Log4Net. The application is based on one of the official ASP.NET Core tutorials, [Create a web API with ASP.NET Core MVC](https://docs.microsoft.com/en-us/aspnet/core/tutorials/first-web-api?view=aspnetcore-2.2&tabs=visual-studio).  
The source code is hosted on [GitHub](https://github.com/satrapu/aspnet-core-logging), while the automatic builds are provided by [Azure DevOps](https://dev.azure.com/satrapu/aspnet-core-logging/_build?definitionId=2&_a=summary).

Development environment
* .NET Core SDK v2.2.101
* Visual Studio 2017 Community Edition v15.9.4
* Windows 10 Pro x64, version 1809

When running *dotnet --info* command from any terminal, I see:
```
dotnet --info
.NET Core SDK (reflecting any global.json):
 Version:   2.2.101
 Commit:    236713b0b7

Runtime Environment:
 OS Name:     Windows
 OS Version:  10.0.17763
 OS Platform: Windows
 RID:         win10-x64
 Base Path:   C:\Program Files\dotnet\sdk\2.2.101\

Host (useful for support):
  Version: 2.2.0
  Commit:  1249f08fed
...
```

<h2 id="logging-in-aspnet-core">Logging support in ASP.NET Core</h2>  
<h3 id="general-info">General information</h3>
ASP.NET Core provides logging support integrated with its dependency injection mechanism via several NuGet packages, the important ones being:
* [Microsoft.Extensions.Logging.Abstractions](https://www.nuget.org/packages/Microsoft.Extensions.Logging.Abstractions)
  * Contains logging infrastructure, like: [ILogger](https://github.com/aspnet/Extensions/blob/master/src/Logging/Logging.Abstractions/src/ILogger.cs), [LoggerExtensions](https://github.com/aspnet/Extensions/blob/master/src/Logging/Logging.Abstractions/src/LoggerExtensions.cs) or [NullLogger](https://github.com/aspnet/Extensions/blob/master/src/Logging/Logging.Abstractions/src/NullLogger.cs) 
* [Microsoft.Extensions.Logging](https://www.nuget.org/packages/Microsoft.Extensions.Logging)
  * Contains default implementations, like: [LoggerFactory](https://github.com/aspnet/Extensions/blob/master/src/Logging/Logging/src/LoggerFactory.cs)  

Microsoft has done a pretty good job on documenting .NET Core and ASP.NET Core and logging is not an exception - see more here:[Logging in ASP.NET Core](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/logging/?view=aspnetcore-2.2).  
A good companion for the aforementioned link is this one: [High-performance logging with LoggerMessage in ASP.NET Core](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/logging/loggermessage?view=aspnetcore-2.2).
  
<h3 id="built-in-logging-providers">Built-in logging providers</h3>
By default, when instantiating a web host builder via the [WebHost.CreateDefaultBuilder](https://docs.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.webhost.createdefaultbuilder?view=aspnetcore-2.1) method in order to start a web application, ASP.NET Core will configure several of its [built-in logging providers](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/logging/?view=aspnetcore-2.2#built-in-logging-providers): 
* Console - found inside [Microsoft.Extensions.Logging.Console](https://www.nuget.org/packages/Microsoft.Extensions.Logging.Console) NuGet package
* Debug - found inside [Microsoft.Extensions.Logging.Debug](https://www.nuget.org/packages/Microsoft.Extensions.Logging.Debug) NuGet package
* Event Source - found inside [Microsoft.Extensions.Logging.EventSource](https://www.nuget.org/packages/Microsoft.Extensions.Logging.EventSource) NuGet package

Here's the code fragment used for configuring these logging providers (as seen inside the decompiled code):
```cs
namespace Microsoft.AspNetCore
{
    public static class WebHost
    {
        ...
        public static IWebHostBuilder CreateDefaultBuilder(string[] args)
        {
            ...ConfigureLogging((Action<WebHostBuilderContext, ILoggingBuilder>) ((hostingContext, logging) =>
            {
                logging.AddConfiguration((IConfiguration) hostingContext.Configuration.GetSection("Logging"));
                logging.AddConsole();
                logging.AddDebug();
                logging.AddEventSourceLogger();
            }))...
        }
        ...
    }
```  

The __console__ logging provider will display log message inside the terminal used for running the web application, so if you start the web app from Visual Studio, this provider is kind of useless.  
Here's several ways of starting an ASP.NET Core web app from CLI (they assume you are inside the solution root folder and you have opened a non-admin PowerShell terminal):
* Using compiled solution:
```powershell
 dotnet .\Sources\TodoWebApp\bin\Debug\netcoreapp2.2\TodoWebApp.dll
```  
* Using source code:
```powershell
 dotnet run --project .\Sources\TodoWebApp\TodoWebApp.csproj
```  
* Using published output:
```powershell
# Generate a self-contained deployment for any Windows OS running on 64 bits
dotnet publish .\Sources\TodoWebApp\TodoWebApp.csproj --self-contained --runtime win-x64
# Run the native EXE
.\Sources\TodoWebApp\bin\Debug\netcoreapp2.2\win-x64\publish\TodoWebApp.exe
```

The __debug__ logging provider will display log messages inside the Visual Studio when starting the web app in debug mode (by default pressing F5 button). I suggest configuring your IDE to redirect all output to the __Immediate Window__ by going to Visual Studio menu -> Tools -> Options -> Debugging -> General and then checking *Redirect all Output Window text to the Immediate Window* option.  

I haven't directly used __event source__ logging provider until now, so please read more about it on its dedicated section found inside the official documentation page, [Logging in ASP.NET Core](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/logging/?view=aspnetcore-2.2#eventsource-provider).

In case you don't need these logging providers, just call the [ClearProviders method](https://docs.microsoft.com/en-us/dotnet/api/microsoft.extensions.logging.loggingbuilderextensions.clearproviders?view=aspnetcore-2.1) before configuring your own, e.g. Log4Net:
```cs
public void ConfigureServices(IServiceCollection services)
{
    // Configure logging
    services.AddLogging(loggingBuilder =>
    {
        // Ensure the built-in logging providers are no longer in use
        loggingBuilder.ClearProviders();
        
        // Configure Log4Net logging provider
        loggingBuilder.AddLog4Net();
    });
    ...
}
```

<h3 id="configure-logging-provider">Configure a logging provider</h3>
The .NET community has provided many logging providers, like: [Log4Net](https://github.com/huorswords/Microsoft.Extensions.Logging.Log4Net.AspNetCore), [NLog](https://github.com/NLog/NLog.Web), [Serilog](https://github.com/serilog/serilog-aspnetcore), etc.  
Pick your favorite one, install the appropriate NuGet package(s), then configure it by adding the proper code in one of __several__ places:
1. Program class, which builds the host running the web application:
```cs
public static class Program
{
        public static void Main(string[] args)
        {
            CreateWebHostBuilder(args).Build()
                                      .Run();
        }

        public static IWebHost CreateWebHostBuilder(string[] args) =>
            WebHost.CreateDefaultBuilder(args)
                   .UseStartup<Startup>()
                   .ConfigureLogging((hostingContext, logging) =>
                   {
                       // Logging provider setup goes here
                   })
                   .Build();
        }
```
2. [Startup class](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/startup?view=aspnetcore-2.2)  
  2.1 [ConfigureServices method](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/startup?view=aspnetcore-2.2#the-configureservices-method):
```cs
public void ConfigureServices(IServiceCollection services)
{
        services.AddLogging(loggingBuilder =>
        {
            // Logging provider setup goes here
        });
        ...
}
```  
  2.2 [Configure method](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/startup?view=aspnetcore-2.2#the-configure-method):
```cs
public void Configure(IApplicationBuilder applicationBuilder
                       , IHostingEnvironment environment
                       , ILoggerFactory loggerFactory)
{
        // Use extensions methods against "loggerFactory" parameter 
        // to setup your logging provider
        ...
}
```

I would personally use either __ConfigureServices__ or __Configure__ method of the Startup class for configuring logging since they allow very complex customizations; on the other hand, I would use the Program class for basic setup and optionally enhancing it with the aforementioned methods.

Here's an example how to configure __Log4Net__ via the __Startup.ConfigureServices__ method:
```cs
public void ConfigureServices(IServiceCollection services)
{
    // Configure logging
    services.AddLogging(loggingBuilder =>
    {
        var log4NetProviderOptions = Configuration.GetSection("Log4NetCore")
                                                  .Get<Log4NetProviderOptions>();
        loggingBuilder.AddLog4Net(log4NetProviderOptions);
        loggingBuilder.SetMinimumLevel(LogLevel.Debug);
    });
    ...
}
```
The code above will read the section named __Log4NetCore__ from the current configuration and will map it to a class, [Log4NetProviderOptions](https://github.com/huorswords/Microsoft.Extensions.Logging.Log4Net.AspNetCore/blob/develop/src/Microsoft.Extensions.Logging.Log4Net.AspNetCore/Log4NetProviderOptions.cs), in order to have access to one of the most important Log4Net configuration properties, like the path to the [XML file](https://logging.apache.org/log4net/release/manual/configuration.html) declaring loggers and appenders.  
Then, the __loggingBuilder.AddLog4Net__ method call will instruct ASP.NET Core to use [Log4NetProvider](https://github.com/huorswords/Microsoft.Extensions.Logging.Log4Net.AspNetCore/blob/develop/src/Microsoft.Extensions.Logging.Log4Net.AspNetCore/Log4NetProvider.cs) class from now on as a factory for all needed [ILogger](https://github.com/aspnet/Extensions/blob/master/src/Logging/Logging.Abstractions/src/ILogger.cs) objects.  
The __loggingBuilder.SetMinimumLevel__ method call is explained [here](https://github.com/huorswords/Microsoft.Extensions.Logging.Log4Net.AspNetCore#net-core-20---logging-debug-level-messages).

<h3 id="using-an-ilogger">Using an ILogger</h3>
When a class needs to log a message, it has to declare a dependency upon the __ILogger\<T\>__ interface; the built-in ASP.NET Core dependency injection will resolve it automatically:
```cs
public class TodoService : ITodoService
{
    private readonly TodoDbContext todoDbContext;
    private readonly ILogger logger;

    public TodoService(TodoDbContext todoDbContext, ILogger<TodoService> logger)
    {
        this.todoDbContext = todoDbContext ?? throw new ArgumentNullException(nameof(todoDbContext));
        this.logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }
    ...
}
```

Then, the class can use its __logger__ field to log a message:
```cs
public IList<TodoItem> GetAll()
{
    if (logger.IsEnabled(LogLevel.Debug))
    {
        logger.LogDebug("GetAll() - BEGIN");
    }

    var result = todoDbContext.TodoItems.ToList();

    if (logger.IsEnabled(LogLevel.Debug))
    {
        logger.LogDebug("GetAll() - END");
    }

    return result;
}
```  

<h2 id="logging-the-current-http-context">Logging the current HTTP context</h2>
One of the best ways offered by ASP.NET Core to handle the current HTTP context and manipulate it it's via a [middleware](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/middleware/?view=aspnetcore-2.2).  
The [middleware](https://github.com/satrapu/aspnet-core-logging/blob/master/Sources/TodoWebApp/Logging/LoggingMiddleware.cs) found inside this particular web application will check whether a particular HTTP context must be logged and exactly what to log via several of its dependencies - to be more exact 2 interfaces - since deciding [when to log](https://github.com/satrapu/aspnet-core-logging/blob/master/Sources/TodoWebApp/Logging/IHttpContextLoggingHandler.cs) should not depend on [what and how to log](https://github.com/satrapu/aspnet-core-logging/blob/master/Sources/TodoWebApp/Logging/IHttpObjectConverter.cs).  
The middleware constructor looks like this:
```cs
public LoggingMiddleware(RequestDelegate nextRequestDelegate
                       , IHttpContextLoggingHandler httpContextLoggingHandler
                       , IHttpObjectConverter httpObjectConverter
                       , ILogger<LoggingMiddleware> logger)
{
    this.nextRequestDelegate = nextRequestDelegate ?? throw new ArgumentNullException(nameof(nextRequestDelegate));
    this.httpContextLoggingHandler = httpContextLoggingHandler ?? throw new ArgumentNullException(nameof(httpContextLoggingHandler));
    this.httpObjectConverter = httpObjectConverter ?? throw new ArgumentNullException(nameof(httpObjectConverter));
    this.logger = logger ?? throw new ArgumentNullException(nameof(logger));
}
```  

The middleware logic looks like this:
```cs

public async Task Invoke(HttpContext httpContext)
{
    if (httpContextLoggingHandler.ShouldLog(httpContext))
    {
        await Log(httpContext);
    }
    else
    {
        await nextRequestDelegate(httpContext);
    }
}

private async Task Log(HttpContext httpContext)
{
    // Code needed to log the given httpContext object
}
```
To enable this middleware, I have created an [extension method](https://github.com/satrapu/aspnet-core-logging/blob/master/Sources/TodoWebApp/Logging/LoggingMiddlewareExtensions.cs) and called it from the [Startup class](https://github.com/satrapu/aspnet-core-logging/blob/master/Sources/TodoWebApp/Startup.cs):
```cs
public void Configure(IApplicationBuilder applicationBuilder, IHostingEnvironment environment)
{
    // Ensure logging middleware is invoked as early as possible
    applicationBuilder.UseHttpLogging();
    ...
}
```

To keep things simple, I have written just one service class implementing __IHttpContextLoggingHandler__ (when to log) and __IHttpObjectConverter__ (what & how to log) interfaces - see [LoggingService class](https://github.com/satrapu/aspnet-core-logging/blob/master/Sources/TodoWebApp/Logging/LoggingService.cs).  

The [HttpContext class](https://docs.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.httpcontext?view=aspnetcore-2.1) contains the [Request](https://docs.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.httpcontext.request?view=aspnetcore-2.1) and [Response](https://docs.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.httpcontext.response?view=aspnetcore-2.1) properties which will be converted to log messages by LoggingService class.  
The log message generated for the request contains the path, query string, headers and the body, while the log message generated for the response contains the headers and the body.   

An __HTTP request__ log message looks like this:
```
2018-12-26 18:18:57,895 [11] DEBUG TodoWebApp.Logging.LoggingMiddleware 
 --- REQUEST 0HLJ82DDDSHQS: BEGIN ---
POST /api/todo HTTP/2.0
Host: localhost
Content-Type: application/json; charset=utf-8

{"Id":-100,"Name":"todo-item-4-testing-ceaa5446ff7940138b8da9a9b7c52b9d","IsComplete":false}
--- REQUEST 0HLJ82DDDSHQS: END ---
```

The accompanying __HTTP response__ log message looks like this:
```
2018-12-26 18:18:58,323 [11] DEBUG TodoWebApp.Logging.LoggingMiddleware 
 --- RESPONSE 0HLJ82DDDSHQS: BEGIN ---
HTTP/2.0 400 BadRequest
Content-Type: application/json; charset=utf-8

{"Id":["The field Id must be between 1 and 9.22337203685478E+18."]}
--- RESPONSE 0HLJ82DDDSHQS: END ---
```
<h3 id="correlation-id">Correlation identifier</h3>
The __0HLJ82DDDSHQS__ string represents the so called *[correlation identifier](https://www.enterpriseintegrationpatterns.com/patterns/messaging/CorrelationIdentifier.html)*, which helps in understanding the user journeys inside the application.  
An HTTP request and its accompanying response will use the same correlation identifier; furthermore, any log message related to this pair should use this identifier too.  
ASP.NET Core offers such correlation identifiers via the [HttpContext.TraceIdentifier](https://docs.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.httpcontext.traceidentifier?view=aspnetcore-2.1) property, available on both the current HTTP request (the __HttpRequest.HttpContext.TraceIdentifier__ property) and response (the __HttpResponse.HttpContext.TraceIdentifier__ property).

<h2 id="implementation">Implementation</h2>  
<h3 id="when-to-log">When to log</h3>
My approach to deciding when to log is based on whether the HTTP request is text-based, expects a text-based response or the request path starts with a given string. The HTTP protocol allows the request to signal its body content type via the [Content-Type](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Type) header, while the expected content type is signaled via the [Accept](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept) header.  
For instance, in case the *Accept* or *Content-Type* header is set to *text/plain*, *application/json* or *application/xml*, the request is seen as *text-based* and thus will be logged; otherwise, the request path is checked and if it starts with */api/* (e.g. */api/todo*), the request will also be seen as *text-based* and will be logged.

Here's the simplified version of my implementation for when to log:
```cs
public class LoggingService : IHttpContextLoggingHandler, IHttpObjectConverter
{
    ...
    private static readonly string[] textBasedHeaderNames = { "Accept", "Content-Type" };
    private static readonly string[] textBasedHeaderValues = { "application/json", "application/xml", "text/" };
    private const string ACCEPTABLE_REQUEST_URL_PREFIX = "/api/";

    public bool ShouldLog(HttpContext httpContext)
    {
        return IsTextBased(httpContext.Request);
    }
    
    private static bool IsTextBased(HttpRequest httpRequest)
    {
        return textBasedHeaderNames.Any(headerName => IsTextBased(httpRequest, headerName))
            || httpRequest.Path.ToUriComponent().StartsWith(ACCEPTABLE_REQUEST_URL_PREFIX);
    }

    private static bool IsTextBased(HttpRequest httpRequest, string headerName)
    {
        return httpRequest.Headers.TryGetValue(headerName, out var headerValues)
            && textBasedHeaderValues.Any(textBasedHeaderValue => headerValues.Any(headerValue => headerValue.StartsWith(textBasedHeaderValue)));
    }
    ...
}
```  
Please note the logic above is just for demo purposes, as most probably *your* production-grade application is very different than this one, so please make sure you provide your own implementation for when to log *before* deploying to production!

<h3 id="what-to-log">What to log</h3>
The __LoggingService__ class is converting both the HTTP request and response following the official HTTP message structure, as documented [here](https://developer.mozilla.org/en-US/docs/Web/HTTP/Messages).  
Converting an HTTP request looks like this:
```cs
private const int REQUEST_SIZE = 1000;
...
public string ToLogMessage(HttpRequest httpRequest)
{
    if (httpRequest == null)
    {
        throw new ArgumentNullException(nameof(httpRequest));
    }

    if (logger.IsEnabled(LogLevel.Debug))
    {
        logger.LogDebug($"Converting HTTP request {httpRequest.HttpContext.TraceIdentifier} ...");
    }

    var stringBuilder = new StringBuilder(REQUEST_SIZE);
    stringBuilder.AppendLine($"--- REQUEST {httpRequest.HttpContext.TraceIdentifier}: BEGIN ---");
    stringBuilder.AppendLine($"{httpRequest.Method} {httpRequest.Path}{httpRequest.QueryString.ToUriComponent()} {httpRequest.Protocol}");

    if (httpRequest.Headers.Any())
    {
        foreach (var header in httpRequest.Headers)
        {
            stringBuilder.AppendLine($"{header.Key}: {header.Value}");
        }
    }

    stringBuilder.AppendLine();
    stringBuilder.AppendLine(httpRequest.Body.ReadAndReset());
    stringBuilder.AppendLine($"--- REQUEST {httpRequest.HttpContext.TraceIdentifier}: END ---");

    var result = stringBuilder.ToString();
    return result;
}
```  

Converting an HTTP response looks like this:
```cs
private const int RESPONSE_SIZE = 1000;
...
public string ToLogMessage(HttpResponse httpResponse)
{
    if (httpResponse == null)
    {
        throw new ArgumentNullException(nameof(httpResponse));
    }

    if (logger.IsEnabled(LogLevel.Debug))
    {
        logger.LogDebug($"Converting HTTP response {httpResponse.HttpContext.TraceIdentifier} ...");
    }

    var stringBuilder = new StringBuilder(RESPONSE_SIZE);
    stringBuilder.AppendLine($"--- RESPONSE {httpResponse.HttpContext.TraceIdentifier}: BEGIN ---");
    stringBuilder.AppendLine($"{httpResponse.HttpContext.Request.Protocol} {httpResponse.StatusCode} {((HttpStatusCode)httpResponse.StatusCode).ToString()}");

    if (httpResponse.Headers.Any())
    {
        foreach (var header in httpResponse.Headers)
        {
            stringBuilder.AppendLine($"{header.Key}: {header.Value}");
        }
    }

    stringBuilder.AppendLine();
    stringBuilder.AppendLine(httpResponse.Body.ReadAndReset());
    stringBuilder.AppendLine($"--- RESPONSE {httpResponse.HttpContext.TraceIdentifier}: END ---");

    var result = stringBuilder.ToString();
    return result;
}
```  

<h3 id="how-to-log">How to log</h3>
The __LoggingMiddleware__ class must read both HTTP request and response in order to log them and must ensure that it will do these things without affecting any following middleware which might also need to read them too.
Both [HttpRequest.Body](https://docs.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.httprequest.body?view=aspnetcore-2.1) and [HttpResponse.Body](https://docs.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.httpresponse.body?view=aspnetcore-2.1) properties are streams which once read, cannot be reset to their initial position; this means that once a middleware has read the stream of any of these properties, the following middleware will have nothing to read from.  
In order to bypass this problem, one can use the [EnableRewind method](https://docs.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.http.internal.bufferinghelper.enablerewind?view=aspnetcore-2.1) against the HTTP request and replace the response body stream with a seekable one.

Enable rewinding the HTTP request stream:
```cs
httpContext.Request.EnableRewind();
```

Replacing the HTTP response stream with a seekable one:
```cs
private const int RESPONSE_BUFFER_SIZE_IN_BYTES = 1024 * 1024;
...
var originalResponseBodyStream = httpContext.Response.Body;

using (var stream = new MemoryStream(RESPONSE_BUFFER_SIZE_IN_BYTES))
{
    // Replace response body stream with a seekable one, like a MemoryStream, to allow logging it
    httpContext.Response.Body = stream;

    // Process current request
    await nextRequestDelegate(httpContext);

    // Logs the current HTTP response
    var httpResponseAsLogMessage = httpObjectConverter.ToLogMessage(httpContext.Response);
    logger.LogDebug(httpResponseAsLogMessage);

    // Ensure the original HTTP response is sent to the next middleware
    await stream.CopyToAsync(originalResponseBodyStream);
}
```

Both above code fragments can be found inside the [LoggingMiddleware.Log method](https://github.com/satrapu/aspnet-core-logging/blob/master/Sources/TodoWebApp/Logging/LoggingMiddleware.cs#L62L89).

<h2 id="conclusion">Conclusion</h2>  
Logging an HTTP context in ASP.NET Core is not an easy task, but as seen above, it can be done.  
Care must be taken when trying to log any large request and response bodies - I'm waiting for David Fowler's [recommendation](https://github.com/davidfowl/AspNetCoreDiagnosticScenarios/blob/master/AspNetCoreGuidance.md#avoid-reading-the-entire-request-body-or-response-body-into-memory)  for avoiding reading the entire request body or response body into memory - unfortunately, at the time of writing this paragraph, it's still not done!  
This article has only scratch the surface of the logging iceberg, but hopefully I will come back with more information helping tackling this very important topic.
