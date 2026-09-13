import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TmdbMovie } from '../../models/movie.model';
import { MovieService } from '../../services/movie.service';

@Component({
  selector: 'app-movie-search',
  imports: [FormsModule],
  templateUrl: './movie-search.html',
  styleUrl: './movie-search.css',
})
export class MovieSearch {
  private readonly movieService = inject(MovieService);

  query = '';
  readonly results = signal<TmdbMovie[]>([]);
  readonly loading = signal(false);
  readonly searched = signal(false);
  readonly errorMessage = signal<string | null>(null);
  readonly addedIds = signal<Set<number>>(new Set());
  readonly addErrorId = signal<number | null>(null);

  search(): void {
    const trimmed = this.query.trim();
    if (!trimmed) {
      return;
    }

    this.loading.set(true);
    this.searched.set(true);
    this.errorMessage.set(null);
    this.addErrorId.set(null);

    this.movieService.search(trimmed).subscribe({
      next: (results) => {
        this.results.set(results);
        this.loading.set(false);
      },
      error: (err) => {
        this.errorMessage.set(
          err.status === 502
            ? 'TMDB no está disponible en este momento. Probá de nuevo en unos minutos.'
            : 'No se pudo completar la búsqueda.',
        );
        this.results.set([]);
        this.loading.set(false);
      },
    });
  }

  addToCollection(movie: TmdbMovie): void {
    this.addErrorId.set(null);
    this.movieService
      .create({
        tmdbId: movie.tmdbId,
        title: movie.title,
        description: movie.description,
        releaseDate: movie.releaseDate,
        posterUrl: movie.posterUrl,
        genre: null,
      })
      .subscribe({
        next: () => this.addedIds.set(new Set([...this.addedIds(), movie.tmdbId])),
        error: () => this.addErrorId.set(movie.tmdbId),
      });
  }

  isAdded(movie: TmdbMovie): boolean {
    return this.addedIds().has(movie.tmdbId);
  }
}
