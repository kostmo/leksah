{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE OverloadedStrings #-}
-----------------------------------------------------------------------------
--
-- Module      :  IDE.Pane.WebKit.Documentation
-- Copyright   :  2007-2011 Juergen Nicklisch-Franken, Hamish Mackenzie
-- License     :  GPL
--
-- Maintainer  :  maintainer@leksah.org
-- Stability   :  provisional
-- Portability :
--
-- |
--
-----------------------------------------------------------------------------

module IDE.Pane.WebKit.Documentation (
    IDEDocumentation(..)
  , DocumentationState(..)
  , getDocumentation
  , loadDoc
  , reloadDoc
) where

import Graphics.UI.Frame.Panes
       (RecoverablePane(..), PanePath, RecoverablePane, Pane(..))
import Data.Typeable (Typeable)
import Data.Text (Text)
import IDE.Core.Types (IDEAction, IDEM)
import Control.Monad.IO.Class (MonadIO(..))
import Graphics.UI.Frame.ViewFrame (getNotebook)
import IDE.Core.State (reifyIDE)
import IDE.Core.State (reflectIDE)
import Graphics.UI.Editor.Basics (Connection(..))
import GI.Gtk.Objects.ScrolledWindow
       (scrolledWindowSetPolicy, scrolledWindowSetShadowType,
        scrolledWindowNew, ScrolledWindow(..))
import GI.WebKit.Objects.WebView
       (webViewReload, webViewGoBack, webViewZoomOut, webViewZoomIn,
        webViewNew, webViewLoadUri, setWebViewZoomLevel, webViewGetUri,
        getWebViewZoomLevel, WebView(..))
import GI.Gtk.Objects.Widget
       (onWidgetKeyPressEvent, afterWidgetFocusInEvent, toWidget)
import GI.Gtk.Objects.Adjustment (noAdjustment)
import GI.Gtk.Enums (PolicyType(..), ShadowType(..))
import GI.Gtk.Objects.Container (containerAdd)
import GI.Gdk (eventKeyReadState, keyvalName, eventKeyReadKeyval)
import GI.Gdk.Flags (ModifierType(..))
import System.Log.Logger (debugM)
import Data.GI.Base.BasicTypes (NullToNothing(..))

data IDEDocumentation = IDEDocumentation {
    scrolledView :: ScrolledWindow
  , webView      :: WebView
} deriving Typeable

data DocumentationState = DocumentationState {
    zoom :: Float
  , uri  :: Maybe Text
} deriving(Eq,Ord,Read,Show,Typeable)

instance Pane IDEDocumentation IDEM
    where
    primPaneName _  =   "Doc"
    getAddedIndex _ =   0
    getTopWidget    =   liftIO . toWidget . scrolledView
    paneId b        =   "*Doc"

instance RecoverablePane IDEDocumentation DocumentationState IDEM where
    saveState p = do
        zoom <- getWebViewZoomLevel $ webView p
        uri  <- nullToNothing . webViewGetUri $ webView p
        return (Just DocumentationState{..})
    recoverState pp DocumentationState {..} = do
        nb     <-  getNotebook pp
        mbPane <- buildPane pp nb builder
        case mbPane of
            Nothing -> return ()
            Just p  -> do
                setWebViewZoomLevel (webView p) zoom
                maybe (return ()) (webViewLoadUri (webView p)) uri
        return mbPane
    builder pp nb windows = reifyIDE $ \ ideR -> do
        scrolledView <- scrolledWindowNew noAdjustment noAdjustment
        scrolledWindowSetShadowType scrolledView ShadowTypeIn

        webView <- webViewNew
        containerAdd scrolledView webView

        scrolledWindowSetPolicy scrolledView PolicyTypeAutomatic PolicyTypeAutomatic
        let docs = IDEDocumentation {..}

        cid1 <- ConnectC webView <$> afterWidgetFocusInEvent webView (\e -> do
            liftIO $ reflectIDE (makeActive docs) ideR
            return True)

        cid2 <- ConnectC webView <$> onWidgetKeyPressEvent webView (\e -> do
            key <- eventKeyReadKeyval e >>= keyvalName
            mod <- eventKeyReadState e
            case (key, mod) of
                ("plus", [ModifierTypeShiftMask,ModifierTypeControlMask]) -> webViewZoomIn  webView >> return True
                ("minus",[ModifierTypeControlMask]) -> webViewZoomOut webView >> return True
                ("BackSpace", [])         -> webViewGoBack  webView >> return True
                _                         -> return False)
        return (Just docs, [cid1, cid2])


getDocumentation :: Maybe PanePath -> IDEM IDEDocumentation
getDocumentation Nothing    = forceGetPane (Right "*Doc")
getDocumentation (Just pp)  = forceGetPane (Left pp)

loadDoc :: Text -> IDEAction
loadDoc uri =
     do doc <- getDocumentation Nothing
        let view = webView doc
        webViewLoadUri view uri

reloadDoc :: IDEAction
reloadDoc =
     do doc <- getDocumentation Nothing
        let view = webView doc
        webViewReload view

