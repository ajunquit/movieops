import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Movie } from '../../models/movie.model';
import { MovieService } from '../../services/movie.service';

@Component({
  selector: 'app-movie-list',
  imports: [RouterLink],
  templateUrl: './movie-list.html',
  styleUrl: './movie-list.css',
})
export class MovieList implements OnInit {
  private readonly movieService = inject(MovieService);

  readonly movies = signal<Movie[]>([]);
  readonly loading = signal(true);
  readonly errorMessage = signal<string | null>(null);

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading.set(true);
    this.errorMessage.set(null);
    this.movieService.getAll().subscribe({
      next: (movies) => {
        this.movies.set(movies);
        this.loading.set(false);
      },
      error: () => {
        this.errorMessage.set('No se pudo cargar la colección de películas.');
        this.loading.set(false);
      },
    });
  }

  remove(movie: Movie): void {
    if (!confirm(`¿Eliminar "${movie.title}" de la colección?`)) {
      return;
    }
    this.movieService.delete(movie.id).subscribe({
      next: () => this.movies.set(this.movies().filter((m) => m.id !== movie.id)),
      error: () => this.errorMessage.set(`No se pudo eliminar "${movie.title}".`),
    });
  }
}
