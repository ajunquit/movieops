using Microsoft.EntityFrameworkCore;
using MovieOps.Application.Interfaces;
using MovieOps.Domain.Entities;

namespace MovieOps.Infrastructure.Persistence.Repositories;

public class MovieRepository(MovieOpsDbContext context) : IMovieRepository
{
    public async Task<Movie?> GetByIdAsync(Guid id, CancellationToken cancellationToken)
    {
        return await context.Movies
            .Include(m => m.CollectionEntry)
            .FirstOrDefaultAsync(m => m.Id == id, cancellationToken);
    }

    public async Task<IReadOnlyList<Movie>> GetAllAsync(CancellationToken cancellationToken)
    {
        return await context.Movies
            .Include(m => m.CollectionEntry)
            .OrderByDescending(m => m.CreatedAt)
            .ToListAsync(cancellationToken);
    }

    public Task<bool> ExistsByTmdbIdAsync(int tmdbId, CancellationToken cancellationToken)
    {
        return context.Movies.AnyAsync(m => m.TmdbId == tmdbId, cancellationToken);
    }

    public async Task AddAsync(Movie movie, CancellationToken cancellationToken)
    {
        await context.Movies.AddAsync(movie, cancellationToken);
    }

    public void Remove(Movie movie)
    {
        context.Movies.Remove(movie);
    }

    public Task SaveChangesAsync(CancellationToken cancellationToken)
    {
        return context.SaveChangesAsync(cancellationToken);
    }
}
