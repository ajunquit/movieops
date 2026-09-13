import { Component, OnInit, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Movie, WATCH_STATUSES, WatchStatus } from '../../models/movie.model';
import { MovieService } from '../../services/movie.service';

@Component({
  selector: 'app-movie-form',
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './movie-form.html',
  styleUrl: './movie-form.css',
})
export class MovieForm implements OnInit {
  private readonly formBuilder = inject(FormBuilder);
  private readonly movieService = inject(MovieService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  readonly watchStatuses = WATCH_STATUSES;
  readonly isEditMode = signal(false);
  readonly errorMessage = signal<string | null>(null);
  readonly collectionErrorMessage = signal<string | null>(null);

  private movieId: string | null = null;

  readonly movieForm = this.formBuilder.group({
    tmdbId: [null as number | null, [Validators.required]],
    title: ['', [Validators.required, Validators.maxLength(300)]],
    description: [''],
    releaseDate: [''],
    posterUrl: [''],
    genre: [''],
  });

  readonly collectionForm = this.formBuilder.group({
    status: ['Watchlist'],
    rating: [null as number | null, [Validators.min(1), Validators.max(10)]],
    comment: [''],
  });

  ngOnInit(): void {
    this.movieId = this.route.snapshot.paramMap.get('id');
    if (this.movieId) {
      this.isEditMode.set(true);
      this.movieForm.get('tmdbId')?.disable();
      this.loadMovie(this.movieId);
    }
  }

  private loadMovie(id: string): void {
    this.movieService.getById(id).subscribe({
      next: (movie) => this.populateForms(movie),
      error: () => this.errorMessage.set('No se pudo cargar la película.'),
    });
  }

  private populateForms(movie: Movie): void {
    this.movieForm.patchValue({
      tmdbId: movie.tmdbId,
      title: movie.title,
      description: movie.description ?? '',
      releaseDate: movie.releaseDate ?? '',
      posterUrl: movie.posterUrl ?? '',
      genre: movie.genre ?? '',
    });
    this.collectionForm.patchValue({
      status: movie.status,
      rating: movie.rating,
      comment: movie.comment ?? '',
    });
  }

  submitMovie(): void {
    if (this.movieForm.invalid) {
      this.movieForm.markAllAsTouched();
      return;
    }

    this.errorMessage.set(null);
    const value = this.movieForm.getRawValue();

    const request$ = this.isEditMode()
      ? this.movieService.update(this.movieId!, {
          title: value.title!,
          description: value.description || null,
          releaseDate: value.releaseDate || null,
          posterUrl: value.posterUrl || null,
          genre: value.genre || null,
        })
      : this.movieService.create({
          tmdbId: value.tmdbId!,
          title: value.title!,
          description: value.description || null,
          releaseDate: value.releaseDate || null,
          posterUrl: value.posterUrl || null,
          genre: value.genre || null,
        });

    request$.subscribe({
      next: (movie) => this.router.navigate(['/movies', movie.id, 'edit']),
      error: (err) => {
        this.errorMessage.set(
          err.status === 409
            ? 'Esa película (TMDB id) ya está en la colección.'
            : 'No se pudo guardar la película.',
        );
      },
    });
  }

  submitCollection(): void {
    if (!this.movieId || this.collectionForm.invalid) {
      this.collectionForm.markAllAsTouched();
      return;
    }

    this.collectionErrorMessage.set(null);
    const value = this.collectionForm.getRawValue();

    this.movieService
      .updateCollection(this.movieId, {
        status: value.status as WatchStatus,
        rating: value.rating,
        comment: value.comment || null,
      })
      .subscribe({
        next: () => this.router.navigate(['/movies']),
        error: () => this.collectionErrorMessage.set('No se pudo actualizar tu colección.'),
      });
  }
}
