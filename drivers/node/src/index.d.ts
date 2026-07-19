/// <reference types="node" />

export class OrbeliasError extends Error {}

export class OrbeliasId {
  readonly parent: bigint;
  readonly epoch: number;
  readonly seq: number;
  readonly tWrite: number;
  readonly period: number;
  readonly head: number;

  constructor(
    parent: bigint | number | string,
    epoch: number | string,
    seq: number | string,
    tWrite: number | string,
    period: number | string,
    head: number | string,
  );

  static parse(text: string): OrbeliasId;
  toString(): string;
}

export interface OrbeliasClientOptions {
  timeout?: number;
  timeoutMs?: number;
}

export interface PutOptions {
  vector?: number[];
  node?: number;
}

export interface ReadOptions {
  node?: number;
}

export class OrbeliasClient {
  readonly peers: Array<{ host: string; port: number }>;
  readonly timeoutMs: number;

  constructor(peers: string | string[], options?: OrbeliasClientOptions);
  static connect(peers: string | string[], options?: OrbeliasClientOptions): OrbeliasClient;

  close(): Promise<void>;
  put(ring: string, payload: Buffer | string, options?: PutOptions): Promise<OrbeliasId>;
  get(id: OrbeliasId, options?: ReadOptions): Promise<Buffer | null>;
  query(id: OrbeliasId, selection: string, options?: ReadOptions): Promise<Buffer | null>;
  health(node?: number): Promise<string>;
}
