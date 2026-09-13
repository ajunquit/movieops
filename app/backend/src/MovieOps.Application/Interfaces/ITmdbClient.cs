using MovieOps.Application.Dtos;

namespace MovieOps.Application.Interfaces;

public interface ITmdbClient
{
    Task<IReadOnlyList<TmdbMovieDto>> SearchAsync(string query, CancellationToken cancellationToken);
}
