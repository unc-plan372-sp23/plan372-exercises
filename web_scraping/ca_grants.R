# Web scraping in R
# This script demonstrates scraping data from a website that does not offer data downloads
# In this case, we'll be scraping grant information from grants.ca.gov.
# Screen scraping can be unreliable, as any change to the website structure will break code that
# scrapes it. Always check your output data carefully.

library(tidyverse)
library(rvest)
library(polite)
library(purrr)

# We're going to be scraping grant opportunities from grants.ca.gov. First, we need to familiarize ourselves
# with the structure of the page. Go to grants.ca.gov, and click on one of the categories to see grants available.
# Open the Chrome inspector.

# first, we establish a connection to grants.ca.gov. If we're scraping multiple pages,
# the session will keep us from scraping too quickly and overwhelming the server,
# and will keep us from scraping pages disallowed in robots.txt
session = bow("https://grants.ca.gov")

# now, let's retrieve the first page of results
res = scrape(session, list("s"=""))

# next, looking at the Chrome inspector, let's find the class for the element that
# contains information about each grant. We use a 
grant_elements = html_elements(res, "")

# we want to parse each grant element into one row of a dataframe. We use map_dfr
# which will call the function on each element of grant_elements and combine the
# results into a data frame
grants = map_dfr(grant_elements, function (element) {
  # We need to extract the data we need from each grant element. We don't need to
  # include the .grant-content__primary class as we are extracting from within each
  # grant element.
  
  # We use a CSS selector to find the link to the grant, and extract the text of the
  # link as this is the grant title
  grant_title = html_element(element, "") %>% html_text2()
  
  # The URL is not text in the page, but the HTML attribute href, so here we extract
  # the attribute.
  grant_url = html_element(element, "") %>% html_attr("href")
  
  # We need to return the values as a named list, with each column of the data frame
  # mapping onto the appropriate value.
  return(list(
    "title"=grant_title,
    "url"=grant_url
  ))
})

# Exercise: extract the grantmaking agency and grant amount

# Like many websites, grants.ca.gov presents information in multiple pages. We need to
# reverse-engineer how their page structure works. Usually information about the pages is
# contained in the URL. Click back and forth on the page selectors and look at the URL to see how
# changing the page changes the URL

# We see that the page structure is fairly simple - changing the url to /page/2 goes to
# page 2, etc. For simplicity I also determined that /page/1 is page 1. We now need to
# program a loop to read each page. There are two main types of loops: for loops and while
# loops. For loops loop over a defined range or items, and while loops loop until a condition
# is no longer true.

# In general, R users avoid loops and use the functions apply, mutate, and map_ instead. But we can't
# use those functions if we don't know how many times we're going to iterate, so we need to use
# a loop here.

# we are going to declare the variable has_next_page here, and we will set it to false
# when there is no longer a next page
has_next_page = TRUE

# This will store the results from each page
results = list()

# This stores which page we are currently on
current_page = 1

while (has_next_page) {
  # we first need to update the URL in our session
  # The nod function updates the URL in the session, and the paste0 function
  # puts together its arguments into a single character string.
  session = nod(session, paste0("/page/", current_page))
  
  # now, we once again scrape the page
  res = scrape(session, list("s"=""))
  
  # and use the same code to extract grants
  grant_elements = html_elements(res, ".grant-content__primary")
  
  grants = map_dfr(grant_elements, function (element) {
    grant_title = html_element(element, "") %>% html_text2()
    grant_url = html_element(element, "") %>% html_attr("href")


    return(list(
      "title"=grant_title,
      "url"=grant_url
    ))
  })
  
  # we now add the grants from this page to the end of our list
  results[[current_page]] = grants
  
  # and update the current page
  current_page = current_page + 1
  
  # and check whether there is a next page by looking at the next page link
  has_next_page = !is.na(html_element(res, "a.pagination__link--next"))
}

# now, we need to put everything together into a data frame
all_grants = bind_rows(results)

# we can save this using the write_csv function
write_csv(all_grants, "all_grants.csv")

# We want to add descriptions to each grant. The descriptions aren't available on the main
# page, so we will have to retrieve the specific grant page for each grant, and extract the
# description. Here, we can use a mutate function instead of a loop, because we know how many
# grants we're retrieving.

# The grants are not on the same server (www.grants.ca.gov vs grants.ca.gov) so we need a
# new session
desc_sess = bow("https://www.grants.ca.gov")

# first, we will define a function to extract the description given a url
# this is a "named function" because we are giving it a name. Above we had an
# "anonymous function" that did not have a name.
get_description = function(url) {
  # first, update the session with the URL
  # <<- is the same as = but will set the variable in the "global scope" so that
  # it will still be available after this function is done. Otherwise, 
  desc_sess <<- nod(desc_sess, url)
  
  # now, retrieve the results. There are no query parameters needed here.
  resp = scrape(desc_sess)
  
  # we then need to inspect one of these pages and find the html element that contains
  # the description. Unfortunately, there's not a unique class or ID we can use to
  # find this. Instead, we will use the :contains CSS selector to find columns that
  # contain the text "Description"
  desc = html_elements(resp, "") %>%
    first() %>%
    html_text2()
  
  return(desc)
}

# rowwise is similar to groupby, except that every row is treated as its own group
# we are only retrieving the first 10 descriptions to avoid hammering the CA Grants
# server with many spurious requests, but it would work for all the grants
with_desc = rowwise(all_grants[1:10,], everything()) %>%
  mutate(description=get_description(url))
