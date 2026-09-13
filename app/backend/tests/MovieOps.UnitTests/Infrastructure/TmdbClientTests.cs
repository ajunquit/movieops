using System.Net;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using MovieOps.Application.Exceptions;
using MovieOps.Infrastructure.External;

namespace MovieOps.UnitTests.Infrastructure;

public class TmdbClientTests
{
    private static readonly TmdbOptions DefaultOptions = new()
    {
        ApiKey = "test-key",
        BaseUrl = "https://api.themoviedb.org/3/",
        ImageBaseUrl = "https://image.tmdb.org/t/p/w500",
    };

    [Fact]
    public async Task SearchAsync_MapsTmdbResponseIntoDtos()
    {
        const string json = """
            {
              "results": [
                {
                  "id": 157336,
                  "title": "Interstellar",
                  "overview": "A team of explorers...",
                  "release_date": "2014-11-05",
                  "poster_path": "/xyz.jpg"
                }
              ]
            }
            """;
        var httpClient = new HttpClient(new FakeHttpMessageHandler(HttpStatusCode.OK, json));
        var sut = new TmdbClient(httpClient, Options(), NullLogger<TmdbClient>.Instance);

        var results = await sut.SearchAsync("interstellar", CancellationToken.None);

        var movie = Assert.Single(results);
        Assert.Equal(157336, movie.TmdbId);
        Assert.Equal("Interstellar", movie.Title);
        Assert.Equal(new DateOnly(2014, 11, 5), movie.ReleaseDate);
        Assert.Equal("https://image.tmdb.org/t/p/w500/xyz.jpg", movie.PosterUrl);
    }

    [Fact]
    public async Task SearchAsync_WhenTmdbReturnsError_ThrowsTmdbUnavailableException()
    {
        var httpClient = new HttpClient(new FakeHttpMessageHandler(HttpStatusCode.Unauthorized, string.Empty));
        var sut = new TmdbClient(httpClient, Options(), NullLogger<TmdbClient>.Instance);

        await Assert.ThrowsAsync<TmdbUnavailableException>(
            () => sut.SearchAsync("batman", CancellationToken.None));
    }

    private static IOptions<TmdbOptions> Options() => Microsoft.Extensions.Options.Options.Create(DefaultOptions);
}
