module Canister::Tasks
  class Base
    def initialize
      @manager = Canister::Manager.instance
    end
  end
end
