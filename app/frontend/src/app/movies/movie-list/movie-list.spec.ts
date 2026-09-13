import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';

import { MovieList } from './movie-list';
import { Movie } from '../../models/movie.model';

const sampleMovie: Movie = {
  id: '11111111-1111-1111-1111-111111111111',
  tmdbId: 1,
  title: 'Interstellar',
  description: null,
  releaseDate: '2014-11-05',
  posterUrl: null,
  genre: 'Sci-Fi',
  status: 'Watchlist',
  rating: null,
  comment: null,
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
};

describe('MovieList', () => {
  let component: MovieList;
  let fixture: ComponentFixture<MovieList>;
  let httpMock: HttpTestingController;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [MovieList],
      providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([])],
    }).compileComponents();

    fixture = TestBed.createComponent(MovieList);
    component = fixture.componentInstance;
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('should load and display movies from the API', () => {
    fixture.detectChanges();

    httpMock.expectOne('/api/movies').flush([sampleMovie]);
    fixture.detectChanges();

    expect(component.movies()).toEqual([sampleMovie]);
    expect(component.loading()).toBe(false);
    const title = fixture.nativeElement.querySelector('td');
    expect(title?.textContent).toContain('Interstellar');
  });

  it('should show an error message when loading fails', () => {
    fixture.detectChanges();

    httpMock.expectOne('/api/movies').flush('boom', { status: 500, statusText: 'Server Error' });
    fixture.detectChanges();

    expect(component.errorMessage()).toBe('No se pudo cargar la colección de películas.');
  });

  it('should delete a movie after confirmation', () => {
    fixture.detectChanges();
    httpMock.expectOne('/api/movies').flush([sampleMovie]);
    fixture.detectChanges();

    vi.spyOn(window, 'confirm').mockReturnValue(true);

    component.remove(sampleMovie);

    httpMock.expectOne(`/api/movies/${sampleMovie.id}`).flush(null);

    expect(component.movies()).toEqual([]);
  });
});
