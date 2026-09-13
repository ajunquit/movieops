using Microsoft.EntityFrameworkCore;
using MovieOps.Domain.Entities;

namespace MovieOps.Infrastructure.Persistence;

public class MovieOpsDbContext(DbContextOptions<MovieOpsDbContext> options) : DbContext(options)
{
    public DbSet<Movie> Movies => Set<Movie>();
    public DbSet<MovieCollection> MovieCollections => Set<MovieCollection>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Movie>(entity =>
        {
            entity.HasKey(m => m.Id);
            entity.Property(m => m.Title).IsRequired().HasMaxLength(300);
            entity.Property(m => m.Genre).HasMaxLength(100);
            entity.HasIndex(m => m.TmdbId).IsUnique();
        });

        modelBuilder.Entity<MovieCollection>(entity =>
        {
            entity.HasKey(c => c.Id);
            entity.HasIndex(c => c.MovieId).IsUnique();
            entity.Property(c => c.Comment).HasMaxLength(2000);
            entity.HasOne(c => c.Movie)
                .WithOne(m => m.CollectionEntry)
                .HasForeignKey<MovieCollection>(c => c.MovieId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
