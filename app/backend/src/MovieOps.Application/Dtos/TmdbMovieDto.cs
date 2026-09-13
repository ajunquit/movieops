namespace MovieOps.Application.Dtos;

public record TmdbMovieDto(
    int TmdbId,
    string Title,
    string? Description,
    DateOnly? ReleaseDate,
    string? PosterUrl);
