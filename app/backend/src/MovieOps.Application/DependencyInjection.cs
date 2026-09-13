using Microsoft.Extensions.DependencyInjection;
using MovieOps.Application.Interfaces;
using MovieOps.Application.Services;

namespace MovieOps.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<IMovieService, MovieService>();
        return services;
    }
}
