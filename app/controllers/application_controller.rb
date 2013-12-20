class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :set_ref, :set_maybe_ref

  def index
    @document = PrismicService.get_document(api.bookmark("homepage"), api, @ref)
    @arguments = api.form("arguments")
                    .orderings("[my.argument.priority desc]")
                    .submit(@ref)
    @references = api.form("references")
                    .submit(@ref)
  end

  def download
    @document = PrismicService.get_document(api.bookmark("download"), api, @ref)

    # Fun trick: in the "body" fragment, only for blocks that are list items containing a single span which is a link,
    # then we override as_html so that it serializes a button instead of a link in a bulleted item.
    @document['article.body'].blocks.each do |block|
      if block.is_a?(Prismic::Fragments::StructuredText::Block::ListItem) && block.spans.length == 1 && block.spans[0].is_a?(Prismic::Fragments::StructuredText::Span::Hyperlink)
        def block.as_html(link_resolver = nil)
          %(<li class="list-unstyled download-button"><a href="#{spans[0].link.url}" class="btn btn-primary" target="_blank">#{as_text}</a></li>)
        end
      end
    end

  end

  def document
    id = params[:id]
    slug = params[:slug]

    @document = PrismicService.get_document(id, api, @ref)

    # This is how an URL gets checked (with a clean redirect if the slug is one that used to be right, but has changed)
    # Of course, you can change slug_checker in prismic_service.rb, depending on your URL strategy.
    @slug_checker = PrismicService.slug_checker(@document, slug)
    if !@slug_checker[:correct]
      render inline: "Document not found", status: :not_found, file: "#{Rails.root}/public/404", layout: false if !@slug_checker[:redirect]
      redirect_to blogpost_path(id, @document.slug), status: :moved_permanently if @slug_checker[:redirect]
    end
  end

  def search
    @documents = api.form("everything")
                    .query(%([[:d = fulltext(document, "#{params[:q]}")]]))
                    .submit(@ref)
  end


  # Actions for the OAuth2 pages (signin, signout, ...)

  def get_callback_url
    callback_url(redirect_uri: request.env['referer'])
  end

  def signin
    url = api.oauth_initiate_url({
      client_id: PrismicService.config("client_id"),
      redirect_uri: get_callback_url,
      scope: "master+releases"
    })
    redirect_to url
  end

  def callback
    access_token = api.oauth_check_token({
      grant_type: "authorization_code",
      code: params[:code],
      redirect_uri: get_callback_url,
      client_id: PrismicService.config("client_id"),
      client_secret: PrismicService.config("client_secret"),
    })
    if access_token
      session['ACCESS_TOKEN'] = access_token
      url = params['redirect_uri'] || root_path
      redirect_to url
    else
      render "Can't sign you in", status: :unauthorized
    end
  end

  def signout
    session['ACCESS_TOKEN'] = nil
    redirect_to :root
  end

  private


  ## before_action methods

  # Setting @ref as the actual ref id being queried, even if it's the master ref.
  # To be used to call the API, for instance: api.form('everything').submit(@ref)
  def set_ref
    @ref = params[:ref].blank? ? api.master_ref.ref : params[:ref]
  end

  # Setting @maybe_ref as the ref id being queried, or nil if it is the master ref.
  # To be used where you want nothing if on master, but something if on another release.
  # For instance:
  #  * you can use it to call Rails routes: document_path(ref: @maybe_ref), which will add "?ref=refid" as a param, but only when needed.
  #  * you can pass it to your link_resolver method, which will use it accordingly.
  def set_maybe_ref
    @maybe_ref = (params[:ref] != '' ? params[:ref] : nil)
  end

  ##

  # Easier access and initialization of the Prismic::API object.
  def api
    @access_token = session['ACCESS_TOKEN']
    @api ||= PrismicService.init_api(@access_token)
  end

end
