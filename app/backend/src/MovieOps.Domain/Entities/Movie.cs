namespace MovieOps.Domain.Entities;

public class Movie
{
    public Guid Id { get; set; }
    public int TmdbId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public DateOnly? ReleaseDate { get; set; }
    public string? PosterUrl { get; set; }
    public string? Genre { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public MovieCollection? CollectionEntry { get; set; }
}
