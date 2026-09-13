using System.ComponentModel.DataAnnotations;

namespace MovieOps.Application.Dtos;

public record CreateMovieDto(
    [Required] int TmdbId,
    [Required, MaxLength(300)] string Title,
    string? Description,
    DateOnly? ReleaseDate,
    string? PosterUrl,
    string? Genre);
