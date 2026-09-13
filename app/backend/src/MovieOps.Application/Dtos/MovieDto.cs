using MovieOps.Domain.Enums;

namespace MovieOps.Application.Dtos;

public record MovieDto(
    Guid Id,
    int TmdbId,
    string Title,
    string? Description,
    DateOnly? ReleaseDate,
    string? PosterUrl,
    string? Genre,
    WatchStatus Status,
    int? Rating,
    string? Comment,
    DateTime CreatedAt,
    DateTime UpdatedAt);
