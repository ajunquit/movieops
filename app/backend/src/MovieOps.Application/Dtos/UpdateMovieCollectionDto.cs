using System.ComponentModel.DataAnnotations;
using MovieOps.Domain.Enums;

namespace MovieOps.Application.Dtos;

public record UpdateMovieCollectionDto(
    WatchStatus? Status,
    [Range(1, 10)] int? Rating,
    string? Comment);
