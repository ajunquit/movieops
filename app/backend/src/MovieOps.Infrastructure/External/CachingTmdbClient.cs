using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using MovieOps.Application.Dtos;
using MovieOps.Application.Interfaces;

namespace MovieOps.Infrastructure.External;

public class CachingTmdbClient(TmdbClient inner, IMemoryCache cache, IOptions<TmdbOptions> options) : ITmdbClient
{
    public async Task<IReadOnlyList<TmdbMovieDto>> SearchAsync(string query, CancellationToken cancellationToken)
    {
        var cacheKey = $"tmdb-search:{query.Trim().ToLowerInvariant()}";

        if (cache.TryGetValue(cacheKey, out IReadOnlyList<TmdbMovieDto>? cached) && cached is not null)
        {
            return cached;
        }

        var results = await inner.SearchAsync(query, cancellationToken);
        cache.Set(cacheKey, results, TimeSpan.FromSeconds(options.Value.CacheDurationSeconds));
        return results;
    }
}
