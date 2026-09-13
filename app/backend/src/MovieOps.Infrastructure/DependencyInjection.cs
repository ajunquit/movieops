using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MovieOps.Application.Interfaces;
using MovieOps.Infrastructure.External;
using MovieOps.Infrastructure.Persistence;
using MovieOps.Infrastructure.Persistence.Repositories;

namespace MovieOps.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("Default")
            ?? throw new InvalidOperationException("Connection string 'Default' is not configured.");

        services.AddDbContext<MovieOpsDbContext>(options => options.UseNpgsql(connectionString));
        services.AddScoped<IMovieRepository, MovieRepository>();

        services.AddOptions<TmdbOptions>()
            .Bind(configuration.GetSection(TmdbOptions.SectionName));

        services.AddMemoryCache();
        services.AddHttpClient<TmdbClient>()
            .AddStandardResilienceHandler();
        services.AddScoped<ITmdbClient, CachingTmdbClient>();

        return services;
    }
}
