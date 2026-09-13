export type WatchStatus = 'Watchlist' | 'Watching' | 'Watched' | 'Favorite';

export const WATCH_STATUSES: WatchStatus[] = ['Watchlist', 'Watching', 'Watched', 'Favorite'];

export interface Movie {
  id: string;
  tmdbId: number;
  title: string;
  description: string | null;
  releaseDate: string | null;
  posterUrl: string | null;
  genre: string | null;
  status: WatchStatus;
  rating: number | null;
  comment: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateMovieRequest {
  tmdbId: number;
  title: string;
  description: string | null;
  releaseDate: string | null;
  posterUrl: string | null;
  genre: string | null;
}

export interface UpdateMovieRequest {
  title: string;
  description: string | null;
  releaseDate: string | null;
  posterUrl: string | null;
  genre: string | null;
}

export interface UpdateMovieCollectionRequest {
  status?: WatchStatus;
  rating?: number | null;
  comment?: string | null;
}
