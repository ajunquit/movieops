using MovieOps.Application.Dtos;

namespace MovieOps.Application.Interfaces;

public interface IMovieService
{
    Task<IReadOnlyList<MovieDto>> GetAllAsync(CancellationToken cancellationToken);
    Task<MovieDto> GetByIdAsync(Guid id, CancellationToken cancellationToken);
    Task<MovieDto> CreateAsync(CreateMovieDto dto, CancellationToken cancellationToken);
    Task<MovieDto> UpdateAsync(Guid id, UpdateMovieDto dto, CancellationToken cancellationToken);
    Task DeleteAsync(Guid id, CancellationToken cancellationToken);
    Task<MovieDto> UpdateCollectionAsync(Guid id, UpdateMovieCollectionDto dto, CancellationToken cancellationToken);
}
