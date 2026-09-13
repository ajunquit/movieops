using MovieOps.Domain.Enums;

namespace MovieOps.Domain.Entities;

public class MovieCollection
{
    public Guid Id { get; set; }
    public Guid MovieId { get; set; }
    public WatchStatus Status { get; set; } = WatchStatus.Watchlist;
    public int? Rating { get; set; }
    public string? Comment { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public Movie Movie { get; set; } = null!;
}
