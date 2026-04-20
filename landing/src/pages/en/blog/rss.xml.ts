import rss from "@astrojs/rss";
import { getCollection } from "astro:content";
import type { APIContext } from "astro";
import { useTranslations } from "../../../i18n";

export async function GET(context: APIContext) {
  const t = useTranslations("en");
  const posts = (
    await getCollection(
      "blog",
      ({ data }) => data.locale === "en" && !data.draft,
    )
  ).sort((a, b) => b.data.publishedAt.getTime() - a.data.publishedAt.getTime());

  const base = import.meta.env.BASE_URL;
  const basePath = base.endsWith("/") ? base : `${base}/`;

  return rss({
    title: `KSeF Hub — ${t.blog.heading}`,
    description: t.blog.subhead,
    site: context.site!,
    items: posts.map((post) => {
      const slug = post.id.split("/").slice(1).join("/");
      return {
        title: post.data.title,
        pubDate: post.data.publishedAt,
        description: post.data.description,
        link: `${basePath}en/blog/${slug}/`,
        categories: post.data.tags,
        author: post.data.author,
      };
    }),
    customData: `<language>en</language>`,
    trailingSlash: true,
  });
}
