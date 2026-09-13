using Moq;
using MovieOps.Application.Dtos;
using MovieOps.Application.Exceptions;
using MovieOps.Application.Interfaces;
using MovieOps.Application.Services;
using MovieOps.Domain.Entities;
using MovieOps.Domain.Enums;

namespace MovieOps.UnitTests.Application;

public class MovieServiceTests
{
    private readonly Mock<IMovieRepository> repository = new();
    private readonly Mock<ITmdbClient> tmdbClient = new();
    private readonly MovieService sut;

    public MovieServiceTests()
    {
        sut = new MovieService(repository.Object, tmdbClient.Object);
    }

    [Fact]
    public async Task CreateAsync_WhenTmdbIdAlreadyExists_ThrowsConflictException()
    {
        repository.Setup(r => r.ExistsByTmdbIdAsync(157336, It.IsAny<CancellationToken>()))
            .ReturnsAsync(true);

        var dto = new CreateMovieDto(157336, "Interstellar", null, null, null, null);

        await Assert.ThrowsAsync<ConflictException>(() => sut.CreateAsync(dto, CancellationToken.None));

        repository.Verify(r => r.AddAsync(It.IsAny<Movie>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task CreateAsync_WhenNew_CreatesMovieWithDefaultWatchlistStatus()
    {
        repository.Setup(r => r.ExistsByTmdbIdAsync(It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(false);

        var dto = new CreateMovieDto(157336, "Interstellar", "desc", new DateOnly(2014, 11, 5), "poster.jpg", "Sci-Fi");

        var result = await sut.CreateAsync(dto, CancellationToken.None);

        Assert.Equal(WatchStatus.Watchlist, result.Status);
        Assert.Equal("Interstellar", result.Title);
        repository.Verify(r => r.AddAsync(It.IsAny<Movie>(), It.IsAny<CancellationToken>()), Times.Once);
        repository.Verify(r => r.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetByIdAsync_WhenNotFound_ThrowsNotFoundException()
    {
        repository.Setup(r => r.GetByIdAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Movie?)null);

        await Assert.ThrowsAsync<NotFoundException>(() => sut.GetByIdAsync(Guid.NewGuid(), CancellationToken.None));
    }

    [Fact]
    public async Task DeleteAsync_WhenFound_RemovesAndSaves()
    {
        var movie = CreateSampleMovie();
        repository.Setup(r => r.GetByIdAsync(movie.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(movie);

        await sut.DeleteAsync(movie.Id, CancellationToken.None);

        repository.Verify(r => r.Remove(movie), Times.Once);
        repository.Verify(r => r.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task UpdateCollectionAsync_WithOnlyRating_DoesNotChangeStatusOrComment()
    {
        var movie = CreateSampleMovie();
        movie.CollectionEntry!.Status = WatchStatus.Watching;
        movie.CollectionEntry!.Comment = "original comment";
        repository.Setup(r => r.GetByIdAsync(movie.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(movie);

        var dto = new UpdateMovieCollectionDto(null, 8, null);

        var result = await sut.UpdateCollectionAsync(movie.Id, dto, CancellationToken.None);

        Assert.Equal(8, result.Rating);
        Assert.Equal(WatchStatus.Watching, result.Status);
        Assert.Equal("original comment", result.Comment);
    }

    [Fact]
    public async Task SearchAsync_DelegatesToTmdbClient()
    {
        var expected = new List<TmdbMovieDto> { new(1, "Movie", null, null, null) };
        tmdbClient.Setup(c => c.SearchAsync("batman", It.IsAny<CancellationToken>()))
            .ReturnsAsync(expected);

        var result = await sut.SearchAsync("batman", CancellationToken.None);

        Assert.Same(expected, result);
    }

    private static Movie CreateSampleMovie()
    {
        var movie = new Movie
        {
            Id = Guid.NewGuid(),
            TmdbId = 157336,
            Title = "Interstellar",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
        };
        movie.CollectionEntry = new MovieCollection
        {
            Id = Guid.NewGuid(),
            MovieId = movie.Id,
            Movie = movie,
            Status = WatchStatus.Watchlist,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow,
        };
        return movie;
    }
}
