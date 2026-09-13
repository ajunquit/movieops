import { Routes } from '@angular/router';
import { MovieForm } from './movies/movie-form/movie-form';
import { MovieList } from './movies/movie-list/movie-list';

export const routes: Routes = [
  { path: '', redirectTo: 'movies', pathMatch: 'full' },
  { path: 'movies', component: MovieList },
  { path: 'movies/new', component: MovieForm },
  { path: 'movies/:id/edit', component: MovieForm },
  { path: '**', redirectTo: 'movies' },
];
