using Microsoft.AspNetCore.Mvc;
using MovieOps.Application.Dtos;
using MovieOps.Application.Interfaces;

namespace MovieOps.Api.Controllers;

[ApiController]
[Route("api/movies")]
public class MoviesController(IMovieService movieService) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<IReadOnlyList<MovieDto>>> GetAll(CancellationToken cancellationToken)
    {
        return Ok(await movieService.GetAllAsync(cancellationToken));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<MovieDto>> GetById(Guid id, CancellationToken cancellationToken)
    {
        return Ok(await movieService.GetByIdAsync(id, cancellationToken));
    }

    [HttpPost]
    public async Task<ActionResult<MovieDto>> Create(CreateMovieDto dto, CancellationToken cancellationToken)
    {
        var movie = await movieService.CreateAsync(dto, cancellationToken);
        return CreatedAtAction(nameof(GetById), new { id = movie.Id }, movie);
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<MovieDto>> Update(Guid id, UpdateMovieDto dto, CancellationToken cancellationToken)
    {
        return Ok(await movieService.UpdateAsync(id, dto, cancellationToken));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken cancellationToken)
    {
        await movieService.DeleteAsync(id, cancellationToken);
        return NoContent();
    }

    [HttpPatch("{id:guid}/collection")]
    public async Task<ActionResult<MovieDto>> UpdateCollection(Guid id, UpdateMovieCollectionDto dto, CancellationToken cancellationToken)
    {
        return Ok(await movieService.UpdateCollectionAsync(id, dto, cancellationToken));
    }

    [HttpGet("search")]
    public async Task<ActionResult<IReadOnlyList<TmdbMovieDto>>> Search([FromQuery] string query, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return BadRequest("Query parameter 'query' is required.");
        }

        return Ok(await movieService.SearchAsync(query, cancellationToken));
    }
}
