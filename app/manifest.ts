import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Evently",
    short_name: "Evently",
    description: "Events, invitations, tickets and check-in in one place.",
    start_url: "/",
    display: "standalone",
    background_color: "#f4f1ea",
    theme_color: "#19181f",
    icons: [{ src: "/favicon.svg", sizes: "any", type: "image/svg+xml" }],
  };
}
