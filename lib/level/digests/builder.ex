defmodule Level.Digests.Builder do
  @moduledoc false

  import Ecto.Query
  import LevelWeb.Router.Helpers

  alias Ecto.Multi
  alias Level.Digests.Compiler
  alias Level.Digests.Options
  alias Level.Posts
  alias Level.Repo
  alias Level.Schemas
  alias Level.Schemas.SpaceUser

  def build(%SpaceUser{} = space_user, %Options{} = opts) do
    space_user =
      space_user
      |> Repo.preload(:space)
      |> Repo.preload(:user)

    space_user
    |> check_skippable(opts)
    |> perform_build()
  end

  defp check_skippable(space_user, %Options{always_build: true} = opts) do
    {:ok, space_user, opts}
  end

  defp check_skippable(space_user, opts) do
    if get_undismissed_inbox_count(space_user) > 0 do
      {:ok, space_user, opts}
    else
      :skip
    end
  end

  defp perform_build({:ok, space_user, opts}) do
    Multi.new()
    |> persist_digest(space_user.space, space_user, opts)
    |> persist_sections(space_user, opts)
    |> Repo.transaction()
    |> after_build(space_user.space)
  end

  defp perform_build(:skip) do
    :skip
  end

  defp persist_digest(multi, space, space_user, opts) do
    subject = "[" <> space.name <> "] " <> opts.title

    params = %{
      space_id: space_user.space_id,
      space_user_id: space_user.id,
      key: opts.key,
      title: opts.title,
      subject: subject,
      to_email: space_user.user.email,
      start_at: opts.start_at,
      end_at: opts.end_at,
      time_zone: opts.time_zone
    }

    changeset =
      %Schemas.Digest{}
      |> Schemas.Digest.create_changeset(params)

    Multi.insert(multi, :digest, changeset)
  end

  defp persist_sections(multi, space_user, opts) do
    Multi.run(multi, :sections, fn %{digest: digest} ->
      sections =
        []
        |> build_inbox_section(digest, space_user, opts)

      {:ok, sections}
    end)
  end

  defp build_inbox_section(sections, digest, space_user, _opts) do
    unread_count = get_unread_inbox_count(space_user)
    read_count = get_read_inbox_count(space_user)
    {summary, summary_html} = inbox_section_summary(unread_count, read_count)

    link_url =
      main_url(LevelWeb.Endpoint, :index, [
        space_user.space.slug,
        "inbox"
      ])

    section_record =
      insert_section!(digest, %{
        title: "Inbox Highlights",
        summary: summary,
        summary_html: summary_html,
        link_text: "View my inbox",
        link_url: link_url,
        rank: 1
      })

    compiled_posts =
      space_user
      |> get_highlighted_inbox_posts()
      |> Compiler.compile_posts()

    insert_posts!(digest, section_record, compiled_posts)
    section = Compiler.compile_section(section_record, compiled_posts)
    [section | sections]
  end

  def inbox_section_summary(0, 0) do
    text = "Congratulations! You've achieved Inbox Zero."
    html = "Congratulations! You&rsquo;ve achieved Inbox Zero."
    {text, html}
  end

  def inbox_section_summary(unread_count, 0) do
    unread_phrase = pluralize(unread_count, "unread post", "unread posts")
    text = "You have #{unread_phrase} in your inbox. Here are some highlights."
    html = "You have <strong>#{unread_phrase}</strong> in your inbox. Here are some highlights."

    {text, html}
  end

  def inbox_section_summary(0, read_count) do
    read_phrase = pluralize(read_count, "post", "posts")

    text =
      "You have #{read_phrase} in your inbox. " <>
        "We recommend dismissing posts from your inbox once you are finished with them."

    html =
      "You have <strong>#{read_phrase}</strong> in your inbox. " <>
        "We recommend dismissing posts from your inbox once you are finished with them."

    {text, html}
  end

  def inbox_section_summary(unread_count, read_count) do
    unread_phrase = pluralize(unread_count, "unread post", "unread posts")
    read_phrase = pluralize(read_count, "post", "posts")

    plaintext =
      "You have #{unread_phrase} and " <>
        "#{read_phrase} you have already seen in your inbox. Here are some highlights."

    html =
      "You have <strong>#{unread_phrase}</strong> and " <>
        "#{read_phrase} you have already seen in your inbox. Here are some highlights."

    {plaintext, html}
  end

  defp get_unread_inbox_count(space_user) do
    space_user
    |> Posts.Query.base_query()
    |> Posts.Query.where_unread_in_inbox()
    |> Posts.Query.count()
    |> Repo.one()
  end

  defp get_read_inbox_count(space_user) do
    space_user
    |> Posts.Query.base_query()
    |> Posts.Query.where_read_in_inbox()
    |> Posts.Query.count()
    |> Repo.one()
  end

  defp get_undismissed_inbox_count(space_user) do
    space_user
    |> Posts.Query.base_query()
    |> Posts.Query.where_undismissed_in_inbox()
    |> Posts.Query.count()
    |> Repo.one()
  end

  defp get_highlighted_inbox_posts(space_user) do
    inner_query =
      space_user
      |> Posts.Query.base_query()
      |> Posts.Query.where_undismissed_in_inbox()
      |> Posts.Query.select_last_activity_at()

    inner_query
    |> subquery()
    |> order_by(desc: :last_activity_at)
    |> limit(5)
    |> Repo.all()
  end

  defp after_build({:ok, data}, space) do
    {:ok, Compiler.compile_digest(space, data.digest, data.sections)}
  end

  defp after_build(_, _) do
    {:error, "An unexpected error occurred"}
  end

  defp pluralize(count, singular, plural) do
    if count == 1 do
      "#{count} #{singular}"
    else
      "#{count} #{plural}"
    end
  end

  # Private persistence functions

  defp insert_section!(digest, params) do
    params =
      Map.merge(params, %{
        space_id: digest.space_id,
        digest_id: digest.id
      })

    %Schemas.DigestSection{}
    |> Schemas.DigestSection.create_changeset(params)
    |> Repo.insert!()
  end

  defp insert_posts!(digest, section, posts) do
    posts
    |> Enum.with_index()
    |> Enum.map(fn {post, rank} ->
      insert_post!(digest, section, post, rank)
    end)
  end

  defp insert_post!(digest, section, post, rank) do
    params = %{
      space_id: digest.space_id,
      digest_id: digest.id,
      digest_section_id: section.id,
      post_id: post.id,
      rank: rank
    }

    %Schemas.DigestPost{}
    |> Schemas.DigestPost.create_changeset(params)
    |> Repo.insert!()
  end
end
