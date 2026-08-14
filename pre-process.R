library(tidyverse)

dat<-read.csv("data/4_trip_public.csv")

transit<-dat%>%
  filter(O_STATE == 42)
transit<-transit%>%
  filter(D_STATE == 42)

transit<-transit%>%
  filter(MODE_AGG == 5)

transit_mode<-transit%>%
  group_by(MODE)%>%
  summarise(n=n())

transit <- transit %>%
  filter(MODE %in% c(14, 21, 22, 23))

write.csv(transit, "data/transit.csv")
