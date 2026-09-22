export const EVENT_COVERS = [
  { id: "/covers/01-future-work.jpg", name: "Future Work" },
  { id: "/covers/02-after-dark.jpg", name: "After Dark" },
  { id: "/covers/03-creative-play.jpg", name: "Creative Play" },
] as const;

export function coverForEventId(id: number): string {
  return EVENT_COVERS[Math.abs(id) % EVENT_COVERS.length].id;
}

export function randomEventCover(): string {
  return EVENT_COVERS[Math.floor(Math.random() * EVENT_COVERS.length)].id;
}
