import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';

import { MovieSearch } from './movie-search';
import { TmdbMovie } from '../../models/movie.model';

const tmdbResult: TmdbMovie = {
  tmdbId: 157336,
  title: 'Interstellar',
  description: 'A team of explorers...',
  releaseDate: '2014-11-05',
  posterUrl: 'https://image.tmdb.org/t/p/w500/x.jpg',
};

describe('MovieSearch', () => {
  let component: MovieSearch;
  let fixture: ComponentFixture<MovieSearch>;
  let httpMock: HttpTestingController;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [MovieSearch],
      providers: [provideHttpClient(), provideHttpClientTesting()],
    }).compileComponents();

    fixture = TestBed.createComponent(MovieSearch);
    component = fixture.componentInstance;
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('should search and display results', () => {
    component.query = 'interstellar';
    component.search();

    const req = httpMock.expectOne((r) => r.url === '/api/movies/search' && r.params.get('query') === 'interstellar');
    req.flush([tmdbResult]);

    expect(component.results()).toEqual([tmdbResult]);
    expect(component.loading()).toBe(false);
  });

  it('should show a degraded-provider message on 502', () => {
    component.query = 'interstellar';
    component.search();

    httpMock.expectOne((r) => r.url === '/api/movies/search').flush('boom', {
      status: 502,
      statusText: 'Bad Gateway',
    });

    expect(component.errorMessage()).toBe('TMDB no está disponible en este momento. Probá de nuevo en unos minutos.');
  });

  it('should add a result to the collection and mark it as added', () => {
    component.addToCollection(tmdbResult);

    const req = httpMock.expectOne('/api/movies');
    expect(req.request.method).toBe('POST');
    expect(req.request.body.tmdbId).toBe(157336);
    req.flush({});

    expect(component.isAdded(tmdbResult)).toBe(true);
  });
});
