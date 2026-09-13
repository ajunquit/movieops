import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideRouter } from '@angular/router';

import { MovieForm } from './movie-form';

describe('MovieForm', () => {
  let component: MovieForm;
  let fixture: ComponentFixture<MovieForm>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [MovieForm],
      providers: [provideHttpClient(), provideRouter([])],
    }).compileComponents();

    fixture = TestBed.createComponent(MovieForm);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
