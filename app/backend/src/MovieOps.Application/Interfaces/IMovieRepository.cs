using MovieOps.Domain.Entities;

namespace MovieOps.Application.Interfaces;

public interface IMovieRepository
{
    Task<Movie?> GetByIdAsync(Guid id, CancellationToken cancellationToken);
    Task<IReadOnlyList<Movie>> GetAllAsync(CancellationToken cancellationToken);
    Task<bool> ExistsByTmdbIdAsync(int tmdbId, CancellationToken cancellationToken);
    Task AddAsync(Movie movie, CancellationToken cancellationToken);
    void Remove(Movie movie);
    Task SaveChangesAsync(CancellationToken cancellationToken);
}
