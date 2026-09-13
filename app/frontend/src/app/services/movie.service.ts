import { HttpClient } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import {
  CreateMovieRequest,
  Movie,
  TmdbMovie,
  UpdateMovieCollectionRequest,
  UpdateMovieRequest,
} from '../models/movie.model';

@Injectable({ providedIn: 'root' })
export class MovieService {
  private readonly baseUrl = '/api/movies';

  constructor(private readonly http: HttpClient) {}

  getAll(): Observable<Movie[]> {
    return this.http.get<Movie[]>(this.baseUrl);
  }

  getById(id: string): Observable<Movie> {
    return this.http.get<Movie>(`${this.baseUrl}/${id}`);
  }

  create(request: CreateMovieRequest): Observable<Movie> {
    return this.http.post<Movie>(this.baseUrl, request);
  }

  update(id: string, request: UpdateMovieRequest): Observable<Movie> {
    return this.http.put<Movie>(`${this.baseUrl}/${id}`, request);
  }

  delete(id: string): Observable<void> {
    return this.http.delete<void>(`${this.baseUrl}/${id}`);
  }

  updateCollection(id: string, request: UpdateMovieCollectionRequest): Observable<Movie> {
    return this.http.patch<Movie>(`${this.baseUrl}/${id}/collection`, request);
  }

  search(query: string): Observable<TmdbMovie[]> {
    return this.http.get<TmdbMovie[]>(`${this.baseUrl}/search`, { params: { query } });
  }
}
