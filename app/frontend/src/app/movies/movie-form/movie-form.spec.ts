import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ActivatedRoute, Router, convertToParamMap, provideRouter } from '@angular/router';

import { MovieForm } from './movie-form';
import { Movie } from '../../models/movie.model';

describe('MovieForm (create mode)', () => {
  let component: MovieForm;
  let fixture: ComponentFixture<MovieForm>;
  let httpMock: HttpTestingController;
  let router: Router;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [MovieForm],
      providers: [provideHttpClient(), provideHttpClientTesting(), provideRouter([])],
    }).compileComponents();

    fixture = TestBed.createComponent(MovieForm);
    component = fixture.componentInstance;
    httpMock = TestBed.inject(HttpTestingController);
    router = TestBed.inject(Router);
    fixture.detectChanges();
  });

  afterEach(() => httpMock.verify());

  it('should not be in edit mode without a route id', () => {
    expect(component.isEditMode()).toBe(false);
  });

  it('should POST a new movie and navigate to its edit page on success', () => {
    vi.spyOn(router, 'navigate').mockResolvedValue(true);

    component.movieForm.setValue({
      tmdbId: 157336,
      title: 'Interstellar',
      description: '',
      releaseDate: '',
      posterUrl: '',
      genre: '',
    });

    component.submitMovie();

    const req = httpMock.expectOne('/api/movies');
    expect(req.request.method).toBe('POST');
    expect(req.request.body.tmdbId).toBe(157336);

    const created: Movie = {
      id: '22222222-2222-2222-2222-222222222222',
      tmdbId: 157336,
      title: 'Interstellar',
      description: null,
      releaseDate: null,
      posterUrl: null,
      genre: null,
      status: 'Watchlist',
      rating: null,
      comment: null,
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-01T00:00:00Z',
    };
    req.flush(created);

    expect(router.navigate).toHaveBeenCalledWith(['/movies', created.id, 'edit']);
  });

  it('should not submit when the movie form is invalid', () => {
    component.movieForm.patchValue({ title: '' });

    component.submitMovie();

    httpMock.expectNone('/api/movies');
  });
});

describe('MovieForm (edit mode)', () => {
  let component: MovieForm;
  let fixture: ComponentFixture<MovieForm>;
  let httpMock: HttpTestingController;
  let router: Router;

  const movieId = '33333333-3333-3333-3333-333333333333';

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [MovieForm],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        {
          provide: ActivatedRoute,
          useValue: { snapshot: { paramMap: convertToParamMap({ id: movieId }) } },
        },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(MovieForm);
    component = fixture.componentInstance;
    httpMock = TestBed.inject(HttpTestingController);
    router = TestBed.inject(Router);
    vi.spyOn(router, 'navigate').mockResolvedValue(true);
    fixture.detectChanges();
  });

  afterEach(() => httpMock.verify());

  it('should load the movie and populate both forms', () => {
    const movie: Movie = {
      id: movieId,
      tmdbId: 157336,
      title: 'Interstellar',
      description: 'desc',
      releaseDate: '2014-11-05',
      posterUrl: null,
      genre: 'Sci-Fi',
      status: 'Watching',
      rating: 7,
      comment: 'so far so good',
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-01T00:00:00Z',
    };

    httpMock.expectOne(`/api/movies/${movieId}`).flush(movie);

    expect(component.isEditMode()).toBe(true);
    expect(component.movieForm.getRawValue().title).toBe('Interstellar');
    expect(component.collectionForm.getRawValue().status).toBe('Watching');
    expect(component.collectionForm.getRawValue().rating).toBe(7);
  });

  it('should PATCH the collection with the submitted values', () => {
    httpMock.expectOne(`/api/movies/${movieId}`).flush({
      id: movieId,
      tmdbId: 1,
      title: 'X',
      description: null,
      releaseDate: null,
      posterUrl: null,
      genre: null,
      status: 'Watchlist',
      rating: null,
      comment: null,
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-01T00:00:00Z',
    } satisfies Movie);

    component.collectionForm.setValue({ status: 'Watched', rating: 9, comment: 'great' });
    component.submitCollection();

    const req = httpMock.expectOne(`/api/movies/${movieId}/collection`);
    expect(req.request.method).toBe('PATCH');
    expect(req.request.body).toEqual({ status: 'Watched', rating: 9, comment: 'great' });
    req.flush({});

    expect(router.navigate).toHaveBeenCalledWith(['/movies']);
  });
});
