Rails.application.routes.draw do
  # Health check endpoint
  get "up" => "rails/health#show", :as => :rails_health_check

  # VTT sprite/thumbs — must come before resources :scenes
  get "scenes/:id", to: "scenes#vtt", id: /.*_thumbs\.vtt|.*_sprite\.jpg/

  root to: "scenes#index"

  resources :scenes, only: [:index, :show, :update] do
    member do
      get :stream, to: "scenes/streams#stream"
      get :stream_mp4, to: "scenes/streams#stream_mp4"
      get :stream_hls, to: "scenes/streams#stream_hls"
      get "stream_hls/:segment", to: "scenes/streams#stream_hls_segment", as: :stream_hls_segment
      get :screenshot
      get "screenshot/:seconds", to: "scenes#screenshot", as: :screenshot_at
      get :preview
      get :webp
      get "vtt/chapter", to: "scenes#chapter_vtt", as: :chapter_vtt
    end
    resources :scene_markers, only: [] do
      member do
        get :stream
        get :preview
      end
    end
  end

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
  end

  resources :tags, only: [:index]

  resources :galleries, only: [:show] do
    member do
      get ":index", to: "galleries#file", as: :file
    end
  end
end
