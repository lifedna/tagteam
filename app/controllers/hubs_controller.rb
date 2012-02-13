class HubsController < ApplicationController
  before_filter :load_hub, :except => [:index, :new, :create]
  before_filter :add_breadcrumb

  access_control do
    allow all, :to => [:index, :items, :show, :custom_republished_feeds, :tag_controls, :search]
    allow logged_in, :to => [:new, :create]
    allow :owner, :of => :hub, :to => [:edit, :update, :destroy, :add_feed]
    allow :superadmin, :hubadmin
  end


  def items
    hub_id = @hub.id
    @search = FeedItem.search(:include => [:tags, :taggings, :feeds]) do
      with(:hub_ids, hub_id)
      order_by('last_updated', :desc)
      paginate :page => params[:page], :per_page => params[:per_page]
    end
    @search.execute!
    render :layout => ! request.xhr?
  end

  def tag_controls

    @already_filtered_for_hub = HubTagFilter.where(:hub_id => @hub.id).includes(:filter).collect{|htf| htf.filter.tag_id == params[:tag_id].to_i}.flatten.include?(true)

    if params[:hub_feed_id].to_i != 0
      @hub_feed = HubFeed.find(params[:hub_feed_id])
      @already_filtered_for_hub_feed = HubFeedTagFilter.where(:hub_feed_id => params[:hub_feed_id].to_i).includes(:filter).collect{|hftf| hftf.filter.tag_id == params[:tag_id].to_i}.flatten.include?(true)
    end

    if params[:hub_feed_item_id].to_i != 0
      @feed_item = FeedItem.find(params[:hub_feed_item_id])
      @already_filtered_for_hub_feed_item = HubFeedItemTagFilter.where(:feed_item_id => params[:hub_feed_item_id].to_i).includes(:filter).collect{|hfitf| hfitf.filter.tag_id == params[:tag_id].to_i}.flatten.include?(true)
    end

    @tag = ActsAsTaggableOn::Tag.find(params[:tag_id])
    respond_to do|format|
      format.html{
        render :layout => ! request.xhr?
      }
    end
  end

  def add_feed
    @feed = Feed.find_or_initialize_by_feed_url(params[:feed_url])

    if @feed.new_record? 
      if @feed.save
        current_user.has_role!(:owner, @feed)
        current_user.has_role!(:creator, @feed)
      else
        # Not valid.
        respond_to do |format|
          # Tell 'em why.
          logger.warn(format.inspect)
          format.json{ render(:text => @feed.errors.full_messages.join('<br/>'), :status => :not_acceptable) and return }
        end
      end
    end

    @hub_feed = HubFeed.new
    @hub_feed.hub = @hub
    @hub_feed.feed = @feed

    respond_to do |format|
      if @hub_feed.save
        current_user.has_role!(:owner, @hub_feed)
        current_user.has_role!(:creator, @hub_feed)
        format.html{ 
          render :text => 'Added that feed'
        }
      else
        format.html{ 
          render(:text => @hub_feed.errors.full_messages.join('<br />'), :status => :not_acceptable)
        }
      end
    end
  end

  def custom_republished_feeds
    @republished_feeds =  RepublishedFeed.select('DISTINCT republished_feeds.*').joins(:accepted_roles => [:users]).where(['roles.name = ? and roles.authorizable_type = ? and roles_users.user_id = ? and hub_id = ?','owner','RepublishedFeed', ((current_user.blank?) ? nil : current_user.id), @hub.id ]).order('updated_at')
 
    respond_to do|format|
      format.html{
        if request.xhr?
          unless @republished_feeds.empty?
            render :partial => 'shared/line_items/republished_feed_choice', :collection => @republished_feeds
          else 
            render :text => 'None yet. You should create a new republished feed from the "publishing" tab on the hub page.'
          end
        else
          render
        end
      }
    end
  end

  def index
    unless current_user.blank?
      @my_hubs = current_user.my(Hub)
    end
    @hubs = Hub.paginate(:page => params[:page], :per_page => params[:per_page])
  end

  def show
  end

  def new
    @hub = Hub.new
  end

  def create
    @hub = Hub.new
    @hub.attributes = params[:hub]
    respond_to do|format|
      if @hub.save
        current_user.has_role!(:owner, @hub)
        current_user.has_role!(:creator, @hub)
        flash[:notice] = 'Added that Hub.'
        format.html {redirect_to hub_path(@hub)}
      else
        flash[:error] = 'Could not add that Hub'
        format.html {render :action => :new}
      end
    end
  end

  def edit
  end

  def update
    @hub.attributes = params[:hub]
    respond_to do|format|
      if @hub.save
        current_user.has_role!(:editor, @hub)
        flash[:notice] = 'Updated!'
        format.html {redirect_to hub_path(@hub)}
      else
        flash[:error] = 'Couldn\'t update!'
        format.html {render :action => :new}
      end
    end
  end

  def destroy
    @hub.destroy
    flash[:notice] = 'Deleted that hub'
    respond_to do|format|
      format.html{
        redirect_to :action => :index
      }
    end
  end

  def search
    unless params[:q].blank?
      @search = Sunspot.new_search ((params[:search_in].blank?) ? [HubFeed,FeedItem,ActsAsTaggableOn::Tag] : params[:search_in].collect{|si| si.constantize})
      hub_id = @hub.id
      @search.build do
        fulltext params[:q]
        with :hub_ids, hub_id
        paginate :page => params[:page], :per_page => cookies[:per_page]
      end

      @search.execute!
    end

    respond_to do|format|
      format.html{
        render :layout => ! request.xhr?
      }
      format.json{ render :json => @search }
    end

  end

  private

  def load_hub
    @hub = Hub.find(params[:id])
    @owners = @hub.owners
    @is_owner = @owners.include?(current_user)
  end

  def add_breadcrumb
    breadcrumbs.add @hub, hub_path(@hub)
  end

end
