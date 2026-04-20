import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

/**
 * Blog collection.
 *
 * Files live in `src/content/blog/{locale}/{slug}.md`. The locale is part of
 * the path convention AND declared explicitly in frontmatter so the schema
 * can validate it. Filter at query time:
 *
 *   getCollection('blog', ({ data }) => data.locale === 'pl' && !data.draft)
 */
const blog = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/blog" }),
  schema: z.object({
    locale: z.enum(["pl", "en"]),
    title: z.string(),
    description: z.string(),
    publishedAt: z.coerce.date(),
    updatedAt: z.coerce.date().optional(),
    draft: z.boolean().default(false),
    tags: z.array(z.string()).default([]),
    author: z.string().default("KSeF Hub"),
  }),
});

export const collections = { blog };
