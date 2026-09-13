using System.Net;

namespace MovieOps.UnitTests.Infrastructure;

internal class FakeHttpMessageHandler(HttpStatusCode statusCode, string content) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var response = new HttpResponseMessage(statusCode)
        {
            Content = new StringContent(content),
        };
        return Task.FromResult(response);
    }
}
