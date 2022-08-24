import '@glif/base-css'
import App from 'next/app'
import Head from 'next/head'
import Script from 'next/script'
import React from 'react'
import { theme, ThemeProvider } from '@glif/react-components'
import { ApolloProvider } from '@apollo/client'
import { SWRConfig } from 'swr'

import { createApolloClient } from '../apolloClient'
import ErrorBoundary from '../src/components/ErrorBoundary'
import JSONLD from '../JSONLD'

const apolloClient = createApolloClient()

class MyApp extends App {
  render() {
    const { Component, pageProps } = this.props
    return (
      <>
        <Head>
          <title>GLIF Staker</title>
          <meta name='description' content='Put your $FIL to work.' />
          <meta
            name='keywords'
            content='Filecoin,Yield,Web,Storage,Blockchain,Crypto,FIL'
          />
          <meta property='og:image' content='/staker-front.jpg' />
          <meta property='og:title' content='GLIF Staker' />
          <meta property='og:description' content='Put your $FIL to work.' />
          <meta property='og:url' content='https://staker.glif.io' />
          <meta name='twitter:title' content='GLIF Wallet' />
          <meta name='twitter:description' content='Put your $FIL to work.' />
          <meta name='twitter:image' content='/staker-front.jpg' />
          <meta name='twitter:card' content='summary_large_image' />
          <meta name='twitter:creator' content='@glifio' key='twhandle' />
          <meta property='og:site_name' content='GLIF Staker' />
          <meta name='twitter:image:alt' content='Put your $FIL to work.' />
          <link
            rel='icon'
            type='image/png'
            sizes='32x32'
            href='/static/favicon-32x32.png'
          />
          <link
            rel='icon'
            type='image/png'
            sizes='16x16'
            href='/static/favicon-32x32.png'
          />
        </Head>
        <Script
          id='json-ld'
          type='application/ld+json'
          // eslint-disable-next-line react/no-danger
          dangerouslySetInnerHTML={{ __html: JSON.stringify(JSONLD) }}
        />
        <ApolloProvider client={apolloClient}>
          <SWRConfig value={{ refreshInterval: 10000 }}>
            <ThemeProvider theme={theme}>
              <ErrorBoundary>
                <Component {...pageProps} />
              </ErrorBoundary>
            </ThemeProvider>
          </SWRConfig>
        </ApolloProvider>
      </>
    )
  }
}

export default MyApp
