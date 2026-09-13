using MovieOps.Application.Dtos;
using MovieOps.Application.Exceptions;
using MovieOps.Application.Interfaces;
using MovieOps.Domain.Entities;

namespace MovieOps.Application.Services;

public class MovieService(IMovieRepository repository, ITmdbClient tmdbClient) : IMovieService
{
    public async Task<IReadOnlyList<MovieDto>> GetAllAsync(CancellationToken cancellationToken)
    {
        var movies = await repository.GetAllAsync(cancellationToken);
        return movies.Select(ToDto).ToList();
    }

    public async Task<MovieDto> GetByIdAsync(Guid id, CancellationToken cancellationToken)
    {
        var movie = await GetMovieOrThrowAsync(id, cancellationToken);
        return ToDto(movie);
    }

    public async Task<MovieDto> CreateAsync(CreateMovieDto dto, CancellationToken cancellationToken)
    {
        if (await repository.ExistsByTmdbIdAsync(dto.TmdbId, cancellationToken))
        {
            throw new ConflictException($"A movie with TMDB id '{dto.TmdbId}' is already in the collection.");
        }

        var now = DateTime.UtcNow;
        var movie = new Movie
        {
            Id = Guid.NewGuid(),
            TmdbId = dto.TmdbId,
            Title = dto.Title,
            Description = dto.Description,
            ReleaseDate = dto.ReleaseDate,
            PosterUrl = dto.PosterUrl,
            Genre = dto.Genre,
            CreatedAt = now,
            UpdatedAt = now
        };
        movie.CollectionEntry = new MovieCollection
        {
            Id = Guid.NewGuid(),
            MovieId = movie.Id,
            Movie = movie,
            CreatedAt = now,
            UpdatedAt = now
        };

        await repository.AddAsync(movie, cancellationToken);
        await repository.SaveChangesAsync(cancellationToken);
        return ToDto(movie);
    }

    public async Task<MovieDto> UpdateAsync(Guid id, UpdateMovieDto dto, CancellationToken cancellationToken)
    {
        var movie = await GetMovieOrThrowAsync(id, cancellationToken);
        movie.Title = dto.Title;
        movie.Description = dto.Description;
        movie.ReleaseDate = dto.ReleaseDate;
        movie.PosterUrl = dto.PosterUrl;
        movie.Genre = dto.Genre;
        movie.UpdatedAt = DateTime.UtcNow;

        await repository.SaveChangesAsync(cancellationToken);
        return ToDto(movie);
    }

    public async Task DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        var movie = await GetMovieOrThrowAsync(id, cancellationToken);
        repository.Remove(movie);
        await repository.SaveChangesAsync(cancellationToken);
    }

    public async Task<MovieDto> UpdateCollectionAsync(Guid id, UpdateMovieCollectionDto dto, CancellationToken cancellationToken)
    {
        var movie = await GetMovieOrThrowAsync(id, cancellationToken);
        var entry = movie.CollectionEntry!;

        if (dto.Status is not null) entry.Status = dto.Status.Value;
        if (dto.Rating is not null) entry.Rating = dto.Rating;
        if (dto.Comment is not null) entry.Comment = dto.Comment;
        entry.UpdatedAt = DateTime.UtcNow;

        await repository.SaveChangesAsync(cancellationToken);
        return ToDto(movie);
    }

    public Task<IReadOnlyList<TmdbMovieDto>> SearchAsync(string query, CancellationToken cancellationToken)
    {
        return tmdbClient.SearchAsync(query, cancellationToken);
    }

    private async Task<Movie> GetMovieOrThrowAsync(Guid id, CancellationToken cancellationToken)
    {
        return await repository.GetByIdAsync(id, cancellationToken)
            ?? throw new NotFoundException($"Movie '{id}' was not found.");
    }

    private static MovieDto ToDto(Movie movie)
    {
        var entry = movie.CollectionEntry;
        return new MovieDto(
            movie.Id,
            movie.TmdbId,
            movie.Title,
            movie.Description,
            movie.ReleaseDate,
            movie.PosterUrl,
            movie.Genre,
            entry?.Status ?? Domain.Enums.WatchStatus.Watchlist,
            entry?.Rating,
            entry?.Comment,
            movie.CreatedAt,
            movie.UpdatedAt);
    }
}
