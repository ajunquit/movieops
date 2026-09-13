using System.ComponentModel.DataAnnotations;

namespace MovieOps.Application.Dtos;

public record UpdateMovieDto(
    [Required, MaxLength(300)] string Title,
    string? Description,
    DateOnly? ReleaseDate,
    string? PosterUrl,
    string? Genre);
