pin "application"
pin "@rails/actioncable", to: "actioncable.esm.js", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "tom-select", to: "https://cdn.jsdelivr.net/npm/tom-select@2.4.3/+esm"
pin "@orchidjs/sifter", to: "https://cdn.jsdelivr.net/npm/@orchidjs/sifter@1.1.0/+esm"
pin "@orchidjs/unicode-variants", to: "https://cdn.jsdelivr.net/npm/@orchidjs/unicode-variants@1.1.2/+esm"
pin "vtt_thumbnails", to: "vtt_thumbnails.js"
pin_all_from "app/javascript/controllers", under: "controllers"
