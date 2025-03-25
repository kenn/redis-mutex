# FROM ruby:2.3.0-alpine

# RUN apk add --no-cache \
#     bash \
#     git \
#     vim

FROM debian:bullseye

SHELL ["/bin/bash","-l","-c"]

# Install dependencies
RUN apt-get update
RUN apt-get install ghostscript shared-mime-info openssl curl gnupg2 dirmngr git-core libcurl4-openssl-dev software-properties-common zlib1g-dev build-essential libssl-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev libffi-dev libpq-dev libmagickcore-6.q16-dev -y

# Install rbenv & ruby-build
RUN git clone https://github.com/rbenv/rbenv.git ~/.rbenv
RUN echo 'export PATH="~/.rbenv/bin:$PATH"' >> ~/.bashrc
RUN echo 'eval "$(rbenv init -)"' >> ~/.bashrc

RUN git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
RUN echo 'export PATH="$HOME/.rbenv/plugins/ruby-build/bin:$PATH"' >> ~/.bashrc

# Install ruby
RUN rbenv rehash
RUN rbenv install 2.3.0
RUN rbenv global 2.3.0