Rails.application.routes.draw do
  # Health check endpoint
  get "up" => "rails/health#show", :as => :rails_health_check

  # VTT sprite/thumbs — must come before resources :videos
  get "videos/:id", to: "videos#vtt", id: /.*_thumbs\.vtt|.*_sprite\.jpg/

  root to: "videos#index"

  resources :videos, only: [:index, :show, :update] do
    member do
      get :stream, to: "videos/streams#stream"
      get :stream_mp4, to: "videos/streams#stream_mp4"
      get :stream_hls, to: "videos/streams#stream_hls"
      get "stream_hls/:segment", to: "videos/streams#stream_hls_segment", as: :stream_hls_segment
      get :screenshot
      get "screenshot/:seconds", to: "videos#screenshot", as: :screenshot_at
      get :preview
      get :webp
      get "vtt/chapter", to: "videos#chapter_vtt", as: :chapter_vtt
    end
    resources :video_markers, only: [] do
      member do
        get :stream
        get :preview
      end
    end
  end

  # Legacy redirects
  get "/scenes", to: redirect("/videos")
  get "/scenes/:id", to: redirect("/videos/%{id}")

  resources :people, only: [:index, :show, :create] do
    collection do
      get :search
    end
    member do
      get :image
    end
  end

  resources :studios, only: [:index, :show] do
    member do
      get :image
    end
  end

  resources :libraries do
    member do
      post :scan
    end
    collection do
      post :detect_kind
    end
  end

  resources :tags, only: [:index, :create] do
    collection do
      get :search
    end
  end

  resources :galleries, only: [:show] do
    member do
      get ":index", to: "galleries#file", as: :file
    end
  end
end
