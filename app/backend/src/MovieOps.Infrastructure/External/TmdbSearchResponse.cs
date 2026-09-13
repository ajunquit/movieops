using System.Text.Json.Serialization;

namespace MovieOps.Infrastructure.External;

internal record TmdbSearchResponse(
    [property: JsonPropertyName("results")] List<TmdbSearchResult> Results);

internal record TmdbSearchResult(
    [property: JsonPropertyName("id")] int Id,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("overview")] string? Overview,
    [property: JsonPropertyName("release_date")] string? ReleaseDate,
    [property: JsonPropertyName("poster_path")] string? PosterPath);
