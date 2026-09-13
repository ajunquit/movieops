using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using MovieOps.Application.Dtos;

namespace MovieOps.IntegrationTests.Api;

public class MoviesApiTests : IClassFixture<MovieOpsApiFactory>
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter() },
    };

    private readonly HttpClient client;

    public MoviesApiTests(MovieOpsApiFactory factory)
    {
        client = factory.CreateClient();
    }

    [Fact]
    public async Task FullLifecycle_Create_Get_Update_UpdateCollection_Delete()
    {
        var createDto = new CreateMovieDto(900001, "Integration Test Movie", "desc", new DateOnly(2020, 1, 1), null, "Drama");

        var createResponse = await client.PostAsJsonAsync("/api/movies", createDto);
        Assert.Equal(HttpStatusCode.Created, createResponse.StatusCode);
        var created = await createResponse.Content.ReadFromJsonAsync<MovieDto>(JsonOptions);
        Assert.NotNull(created);

        var getResponse = await client.GetAsync($"/api/movies/{created!.Id}");
        Assert.Equal(HttpStatusCode.OK, getResponse.StatusCode);

        var updateDto = new UpdateMovieDto("Updated Title", "desc", new DateOnly(2020, 1, 1), null, "Drama");
        var updateResponse = await client.PutAsJsonAsync($"/api/movies/{created.Id}", updateDto);
        Assert.Equal(HttpStatusCode.OK, updateResponse.StatusCode);
        var updated = await updateResponse.Content.ReadFromJsonAsync<MovieDto>(JsonOptions);
        Assert.Equal("Updated Title", updated!.Title);

        var collectionDto = new UpdateMovieCollectionDto(MovieOps.Domain.Enums.WatchStatus.Watched, 9, "Great movie");
        var collectionResponse = await client.PatchAsJsonAsync($"/api/movies/{created.Id}/collection", collectionDto);
        Assert.Equal(HttpStatusCode.OK, collectionResponse.StatusCode);
        var withCollection = await collectionResponse.Content.ReadFromJsonAsync<MovieDto>(JsonOptions);
        Assert.Equal(MovieOps.Domain.Enums.WatchStatus.Watched, withCollection!.Status);
        Assert.Equal(9, withCollection.Rating);

        var deleteResponse = await client.DeleteAsync($"/api/movies/{created.Id}");
        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);

        var getAfterDelete = await client.GetAsync($"/api/movies/{created.Id}");
        Assert.Equal(HttpStatusCode.NotFound, getAfterDelete.StatusCode);
    }

    [Fact]
    public async Task Create_WithDuplicateTmdbId_ReturnsConflict()
    {
        var dto = new CreateMovieDto(900002, "Duplicate Movie", null, null, null, null);

        var first = await client.PostAsJsonAsync("/api/movies", dto);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);

        var second = await client.PostAsJsonAsync("/api/movies", dto);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
    }

    [Fact]
    public async Task GetById_WhenMovieDoesNotExist_ReturnsNotFound()
    {
        var response = await client.GetAsync($"/api/movies/{Guid.NewGuid()}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
