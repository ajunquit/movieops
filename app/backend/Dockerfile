# ---- build stage ----
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/MovieOps.Domain/MovieOps.Domain.csproj src/MovieOps.Domain/
COPY src/MovieOps.Application/MovieOps.Application.csproj src/MovieOps.Application/
COPY src/MovieOps.Infrastructure/MovieOps.Infrastructure.csproj src/MovieOps.Infrastructure/
COPY src/MovieOps.Api/MovieOps.Api.csproj src/MovieOps.Api/
RUN dotnet restore src/MovieOps.Api/MovieOps.Api.csproj

COPY src/ src/
RUN dotnet publish src/MovieOps.Api/MovieOps.Api.csproj -c Release -o /app --no-restore

# ---- runtime stage ----
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app .

ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=5 \
    CMD curl -f http://localhost:8080/health/live || exit 1

ENTRYPOINT ["dotnet", "MovieOps.Api.dll"]
