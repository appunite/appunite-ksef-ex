defmodule KsefHubWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: KsefHubWeb.Gettext

  alias Phoenix.HTML.Form, as: HtmlForm
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :warning, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-bottom toast-end z-50"
      {@rest}
    >
      <div class={[
        "w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap rounded-md p-4 flex gap-3 items-start border",
        @kind == :info && "bg-background border-border",
        @kind == :warning && "bg-warning/5 border-warning/20",
        @kind == :error && "bg-shad-destructive/5 border-shad-destructive/20"
      ]}>
        <.icon
          :if={@kind == :info}
          name="hero-information-circle"
          class="size-5 shrink-0 text-muted-foreground"
        />
        <.icon
          :if={@kind == :warning}
          name="hero-exclamation-triangle"
          class="size-5 shrink-0 text-warning/70"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="size-5 shrink-0 text-error/70"
        />
        <div class="text-sm">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a badge with semantic colour variants.

  ## Examples

      <.badge>Default</.badge>
      <.badge variant="success">Active</.badge>
      <.badge variant="warning">Pending</.badge>
  """
  attr :variant, :string,
    values: ~w(success warning error info muted default),
    default: "default"

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec badge(map()) :: Phoenix.LiveView.Rendered.t()
  def badge(assigns) do
    variant_classes = %{
      "success" => "bg-success/10 text-success border-success/20",
      "warning" => "bg-warning/10 text-warning border-warning/20",
      "error" => "bg-error/10 text-error border-error/20",
      "info" => "bg-info/10 text-info border-info/20",
      "muted" => "bg-muted text-muted-foreground border-border",
      "default" => "bg-muted text-muted-foreground border-border"
    }

    assigns = assign(assigns, :variant_class, Map.fetch!(variant_classes, assigns.variant))

    ~H"""
    <span
      class={[
        "inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border",
        @variant_class,
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders a card container with rounded border and background.

  ## Examples

      <.card>Content</.card>
      <.card padding="p-4">Compact content</.card>
  """
  attr :class, :string, default: nil
  attr :padding, :string, default: "p-6"
  attr :rest, :global
  slot :inner_block, required: true

  @spec card(map()) :: Phoenix.LiveView.Rendered.t()
  def card(assigns) do
    ~H"""
    <div class={["rounded-xl border border-border bg-card text-card-foreground", @class]} {@rest}>
      <div class={@padding}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders an authentication page card — centered container with heading and optional footer.

  ## Examples

      <.auth_card title="Log in">
        <.simple_form ...>...</.simple_form>
        <:footer>
          <.link navigate={~p"/users/register"}>Sign up</.link>
        </:footer>
      </.auth_card>
  """
  attr :title, :string, required: true
  slot :inner_block, required: true
  slot :footer

  @spec auth_card(map()) :: Phoenix.LiveView.Rendered.t()
  def auth_card(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center">
      <div class="rounded-xl border border-border bg-card text-card-foreground w-full max-w-md">
        <div class="p-6">
          <h2 data-testid="page-title" class="text-2xl font-semibold text-center mb-4">
            {@title}
          </h2>
          {render_slot(@inner_block)}
          <div :for={footer <- @footer}>
            {render_slot(footer)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
      <.button size="sm" variant="ghost">Small</.button>
      <.button size="icon" variant="ghost"><.icon name="hero-pencil" /></.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string, default: nil
  attr :variant, :string, values: ~w(primary outline ghost destructive success warning)
  attr :size, :string, values: ~w(default sm icon), default: "default"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90",
      "outline" =>
        "border border-input bg-background hover:bg-shad-accent hover:text-shad-accent-foreground",
      "ghost" => "hover:bg-shad-accent hover:text-shad-accent-foreground",
      "destructive" =>
        "bg-shad-destructive text-shad-destructive-foreground hover:bg-shad-destructive/90",
      "success" => "bg-emerald-600 text-white hover:bg-emerald-600/90",
      "warning" => "bg-amber-500 text-white hover:bg-amber-500/90",
      nil => "bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90"
    }

    sizes = %{
      "default" => "h-9 px-4 py-2 text-sm",
      "sm" => "h-7 px-2 text-xs",
      "icon" => "h-9 w-9 p-0"
    }

    assigns =
      assign(assigns, :computed_class, [
        "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50 cursor-pointer",
        Map.fetch!(sizes, assigns.size),
        Map.fetch!(variants, assigns[:variant]),
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@computed_class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@computed_class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders the application logo with icon and text.

  ## Examples

      <.logo href={~p"/"} />
  """
  attr :href, :string, required: true
  attr :class, :string, default: nil

  @spec logo(map()) :: Phoenix.LiveView.Rendered.t()
  def logo(assigns) do
    ~H"""
    <a href={@href} class={["flex items-center gap-2", @class]}>
      <.icon name="hero-document-text" class="size-5 text-foreground" />
      <span class="flex flex-col items-start leading-tight">
        <span class="text-sm font-bold tracking-tight">Invoi</span>
        <span class="text-[9px] text-muted-foreground font-normal -mt-0.5">by Appunite</span>
      </span>
    </a>
    """
  end

  @doc """
  Renders a navigation item list for the sidebar/dropdown menus.

  ## Examples

      <.nav_item_list items={nav_items(@company, @role)} current_path={@current_path} />
  """
  attr :items, :list, required: true
  attr :current_path, :string, default: nil

  @spec nav_item_list(map()) :: Phoenix.LiveView.Rendered.t()
  def nav_item_list(assigns) do
    ~H"""
    <%= for item <- @items do %>
      <div
        :if={item.section}
        class="px-2 pt-2 text-xs font-medium text-muted-foreground"
      >
        {item.section}
      </div>
      <a
        href={item.path}
        class={[
          "flex items-center gap-2 px-2 py-1.5 text-sm rounded-sm transition-colors",
          nav_active?(@current_path, item.path) &&
            "font-medium text-foreground bg-shad-accent",
          !nav_active?(@current_path, item.path) &&
            "text-muted-foreground hover:bg-shad-accent hover:text-shad-accent-foreground"
        ]}
      >
        <.icon name={item.icon} class="size-4" />
        {item.label}
      </a>
    <% end %>
    """
  end

  @spec nav_active?(String.t() | nil, String.t()) :: boolean()
  defp nav_active?(nil, _path), do: false

  defp nav_active?(current, path),
    do: current == path || Regex.match?(~r/^#{Regex.escape(path)}(\/|$)/, current)

  @doc """
  Renders a file upload dropzone with drag-and-drop support.

  ## Examples

      <.file_upload_dropzone upload={@uploads.certificate} label="Certificate File (.p12 / .pfx)">
        <p :for={entry <- @uploads.certificate.entries} class="mt-2 text-sm">
          {entry.client_name}
        </p>
      </.file_upload_dropzone>
  """
  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :label, :string, required: true
  slot :inner_block

  @spec file_upload_dropzone(map()) :: Phoenix.LiveView.Rendered.t()
  def file_upload_dropzone(assigns) do
    ~H"""
    <div class="space-y-1">
      <label class="label">
        <span class="text-sm font-medium">{@label}</span>
      </label>
      <div
        class="border-2 border-dashed border-border rounded-lg p-6 text-center"
        phx-drop-target={@upload.ref}
      >
        <.live_file_input
          upload={@upload}
          class="h-9 w-full rounded-md border border-input bg-background text-sm file:border-0 file:bg-muted file:text-muted-foreground file:text-sm file:font-medium file:mr-3 file:px-3 file:h-full"
        />
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to HtmlForm.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        HtmlForm.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="space-y-1.5 mb-2">
      <label class="flex items-center gap-2">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "size-4 rounded border border-input bg-background accent-shad-primary"}
          {@rest}
        />
        <span class="text-sm font-medium">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="space-y-1.5 mb-2">
      <label>
        <span :if={@label} class="text-sm font-medium mb-1.5 block">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
            @errors != [] && (@error_class || "border-error")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {HtmlForm.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="space-y-1.5 mb-2">
      <label>
        <span :if={@label} class="text-sm font-medium mb-1.5 block">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full min-h-[80px] rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
            @errors != [] && (@error_class || "border-error")
          ]}
          {@rest}
        >{HtmlForm.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="space-y-1.5 mb-2">
      <label>
        <span :if={@label} class="text-sm font-medium mb-1.5 block">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={HtmlForm.normalize_value(@type, @value)}
          class={[
            @class ||
              "w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
            @errors != [] && (@error_class || "border-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart phx-submit phx-change phx-update phx-trigger-action),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  @spec simple_form(map()) :: Phoenix.LiveView.Rendered.t()
  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="space-y-4">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-6 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders an error message.

  ## Examples

      <.error>Something went wrong</.error>
  """
  slot :inner_block, required: true

  @spec error(map()) :: Phoenix.LiveView.Rendered.t()
  def error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-shad-destructive">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[
      @actions != [] && "flex items-center justify-between gap-6",
      "pb-4 border-b border-border"
    ]}>
      <div>
        <h1 class="text-lg font-semibold leading-7 tracking-tight">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-muted-foreground mt-0.5">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
    attr :class, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-border">
          <th
            :for={col <- @col}
            class={[
              "text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide",
              col[:class]
            ]}
          >
            {col[:label]}
          </th>
          <th :if={@action != []} class="py-3 px-4">
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class="border-b border-border/50 hover:bg-muted/50 transition-colors"
        >
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={["py-3.5 px-4", @row_click && "hover:cursor-pointer", col[:class]]}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 py-3.5 px-4 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <dl class="space-y-0 divide-y divide-border">
      <div :for={item <- @item} class="flex justify-between gap-4 py-2.5">
        <dt class="text-sm font-medium text-muted-foreground">{item.title}</dt>
        <dd class="text-sm text-right">{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a removable filter chip/pill showing an active filter.

  ## Examples

      <.filter_chip key="status" label="Status" value="Pending" />
  """
  attr :key, :string, required: true, doc: "phx-value-key for the remove event"
  attr :label, :string, required: true, doc: "filter label, e.g. \"Status\""
  attr :value, :string, required: true, doc: "filter value, e.g. \"Pending\""

  @spec filter_chip(map()) :: Phoenix.LiveView.Rendered.t()
  def filter_chip(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 rounded-md bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
      {@label}: {@value}
      <button
        type="button"
        phx-click="remove_filter"
        phx-value-key={@key}
        class="ml-0.5 hover:text-foreground cursor-pointer"
        aria-label={"Remove #{@label} filter"}
      >
        <.icon name="hero-x-mark" class="size-3" />
      </button>
    </span>
    """
  end

  @doc """
  Renders a filter toolbar with a "Filters N" popover button and optional search input.

  Filter fields are rendered inside a JS-toggled popover via the `:filter_fields` slot.
  The parent LiveView should wrap this component in a `<.form>` with `phx-change="filter"`.
  The popover stays open across LiveView patches so users can tweak multiple filters
  and see results update in real-time. Click away or use the toggle button to close.

  ## Examples

      <.form for={@form} phx-change="filter" class="contents">
        <.filter_bar
          active_filters={@active_filters}
          filter_count={@filter_count}
          search_name={@form[:query].name}
          search_value={@form[:query].value}
        >
          <:filter_fields>
            <!-- filter selects here -->
          </:filter_fields>
        </.filter_bar>
      </.form>
  """
  attr :active_filters, :list,
    default: [],
    doc: "list of %{key, label, value} for active filter chips"

  attr :filter_count, :integer, default: 0, doc: "number of active filters"
  attr :search_name, :string, default: nil, doc: "form field name for search input; nil hides it"
  attr :search_value, :string, default: "", doc: "current search value"
  attr :search_placeholder, :string, default: "Search..."

  slot :filter_fields, required: true, doc: "rendered inside the popover"

  @spec filter_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def filter_bar(assigns) do
    ~H"""
    <div class="space-y-2 mt-4 mb-6">
      <div class="flex items-center gap-3">
        <%!-- Filters popover --%>
        <div class="relative">
          <button
            type="button"
            phx-click={JS.toggle(to: "#filter-popover")}
            class="inline-flex items-center gap-2 h-9 px-4 text-sm font-medium rounded-md border border-input bg-background hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer"
          >
            <.icon name="hero-funnel" class="size-4" /> Filters
            <span
              :if={@filter_count > 0}
              class="inline-flex items-center justify-center size-5 rounded-full bg-shad-primary text-shad-primary-foreground text-xs font-medium"
            >
              {@filter_count}
            </span>
          </button>
          <div
            id="filter-popover"
            class="hidden absolute left-0 top-full z-10 mt-1 w-72 rounded-md border border-border bg-background p-4 shadow-md"
            phx-click-away={JS.hide(to: "#filter-popover")}
          >
            <div class="space-y-3">
              {render_slot(@filter_fields)}
            </div>
            <div class="mt-3 pt-3 border-t border-border">
              <button
                type="button"
                phx-click={JS.push("clear_filters") |> JS.hide(to: "#filter-popover")}
                class="inline-flex items-center justify-center h-9 px-3 text-sm font-medium rounded-md hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer w-full"
              >
                Clear all filters
              </button>
            </div>
          </div>
        </div>

        <%!-- Search input --%>
        <div :if={@search_name} class="ml-auto w-72">
          <div class="relative">
            <.icon
              name="hero-magnifying-glass"
              class="absolute left-2.5 top-2.5 size-4 text-muted-foreground"
            />
            <input
              type="text"
              name={@search_name}
              value={@search_value}
              placeholder={@search_placeholder}
              phx-debounce="300"
              class="w-full h-9 rounded-md border border-input bg-background pl-8 pr-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
        </div>
      </div>

      <%!-- Active filter chips --%>
      <div :if={@active_filters != []} class="flex flex-wrap gap-1.5">
        <.filter_chip
          :for={filter <- @active_filters}
          key={filter.key}
          label={filter.label}
          value={filter.value}
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a standalone pagination footer with page info and navigation.

  ## Examples

      <.pagination
        page={@page} per_page={@per_page}
        total_count={@total_count} total_pages={@total_pages}
        base_url={~p"/c/\#{id}/invoices"}
        params={@filter_params}
        noun="invoices"
      />
  """
  attr :page, :integer, required: true
  attr :per_page, :integer, required: true
  attr :total_count, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :base_url, :string, required: true, doc: "base path without query params"
  attr :params, :map, default: %{}, doc: "filter params (without page)"
  attr :noun, :string, default: "results"

  @spec pagination(map()) :: Phoenix.LiveView.Rendered.t()
  def pagination(assigns) do
    ~H"""
    <div class="flex items-center justify-between" data-testid="pagination">
      <p class="text-sm text-muted-foreground">
        <span :if={@total_count > 0}>
          Showing {(@page - 1) * @per_page + 1}–{min(@page * @per_page, @total_count)} of {@total_count} {@noun}
        </span>
        <span :if={@total_count == 0}>
          No {@noun}
        </span>
      </p>

      <div class="flex items-center gap-1">
        <.link
          :if={@page > 1}
          patch={"#{@base_url}?#{URI.encode_query(Map.put(@params, "page", @page - 1))}"}
          class="inline-flex items-center justify-center h-9 px-3 text-sm rounded-md border border-input bg-background hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors"
        >
          Previous
        </.link>
        <span
          :if={@page <= 1}
          class="inline-flex items-center justify-center h-9 px-3 text-sm rounded-md border border-input bg-background transition-colors opacity-50 pointer-events-none"
        >
          Previous
        </span>

        <span class="inline-flex items-center justify-center h-9 px-3 text-sm text-muted-foreground">
          Page {@page} of {@total_pages}
        </span>

        <.link
          :if={@page < @total_pages}
          patch={"#{@base_url}?#{URI.encode_query(Map.put(@params, "page", @page + 1))}"}
          class="inline-flex items-center justify-center h-9 px-3 text-sm rounded-md border border-input bg-background hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors"
        >
          Next
        </.link>
        <span
          :if={@page >= @total_pages}
          class="inline-flex items-center justify-center h-9 px-3 text-sm rounded-md border border-input bg-background transition-colors opacity-50 pointer-events-none"
        >
          Next
        </span>
      </div>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(KsefHubWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(KsefHubWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
