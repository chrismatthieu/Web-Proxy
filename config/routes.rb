Proxy::Application.routes.draw do
  match 'proxy' => 'proxy#proxy'
  root :to => "proxy#index"
end
