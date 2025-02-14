#!/bin/bash

HUGO_BUILD_COMMAND="hugo --gc --minify"

if [[ -n "${CF_PAGES_URL}" ]]; then
  if [ "$CF_PAGES_BRANCH" == "main" ]; then
    ${HUGO_BUILD_COMMAND}
  else
    ${HUGO_BUILD_COMMAND} --baseURL "${CF_PAGES_URL}"
  fi
else
  ${HUGO_BUILD_COMMAND}
fi
