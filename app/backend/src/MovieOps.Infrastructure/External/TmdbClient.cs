using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MovieOps.Application.Dtos;
using MovieOps.Application.Exceptions;
using MovieOps.Application.Interfaces;

namespace MovieOps.Infrastructure.External;

public class TmdbClient : ITmdbClient
{
    private readonly HttpClient httpClient;
    private readonly TmdbOptions options;
    private readonly ILogger<TmdbClient> logger;

    public TmdbClient(HttpClient httpClient, IOptions<TmdbOptions> options, ILogger<TmdbClient> logger)
    {
        this.httpClient = httpClient;
        this.options = options.Value;
        this.logger = logger;

        this.httpClient.BaseAddress = new Uri(this.options.BaseUrl);
        this.httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", this.options.ApiKey);
    }

    public async Task<IReadOnlyList<TmdbMovieDto>> SearchAsync(string query, CancellationToken cancellationToken)
    {
        try
        {
            var response = await httpClient.GetAsync(
                $"search/movie?query={Uri.EscapeDataString(query)}&include_adult=false",
                cancellationToken);

            response.EnsureSuccessStatusCode();

            var payload = await response.Content.ReadFromJsonAsync<TmdbSearchResponse>(cancellationToken);
            var results = payload?.Results ?? [];

            return results.Select(ToDto).ToList();
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or Polly.ExecutionRejectedException)
        {
            logger.LogWarning(ex, "TMDB search failed for query '{Query}'", query);
            throw new TmdbUnavailableException("The TMDB service is currently unavailable.", ex);
        }
    }

    private TmdbMovieDto ToDto(TmdbSearchResult result)
    {
        DateOnly? releaseDate = DateOnly.TryParse(result.ReleaseDate, out var parsed) ? parsed : null;
        var posterUrl = result.PosterPath is null ? null : $"{options.ImageBaseUrl}{result.PosterPath}";

        return new TmdbMovieDto(result.Id, result.Title, result.Overview, releaseDate, posterUrl);
    }
}
