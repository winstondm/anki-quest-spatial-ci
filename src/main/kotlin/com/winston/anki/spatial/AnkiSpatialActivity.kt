package com.winston.anki.spatial

import android.os.Bundle
import androidx.activity.ComponentActivity
import com.meta.spatial.app.PanelRegistration
import com.meta.spatial.toolkit.ActivityPanelRegistration
import com.meta.spatial.toolkit.UIPanelSettings
import com.meta.spatial.scene.Entity
import com.meta.spatial.scene.Transform
import com.meta.spatial.math.Pose
import com.meta.spatial.math.Vector3
import com.ichi2.anki.CollectionOpenActivity
import com.ichi2.anki.Reviewer
import com.winston.anki.spatial.R

class AnkiSpatialActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val deckPanel: PanelRegistration = ActivityPanelRegistration(
            registrationId = R.id.panel_decks,
            classIdCreator = { CollectionOpenActivity::class.java },
            settingsCreator = {
                UIPanelSettings().apply {
                    minWidthMeters = 0.9f
                    minHeightMeters = 0.6f
                    canResize = true
                    canClose = true
                }
            }
        )

        val reviewPanel: PanelRegistration = ActivityPanelRegistration(
            registrationId = R.id.panel_review,
            classIdCreator = { Reviewer::class.java },
            settingsCreator = {
                UIPanelSettings().apply {
                    minWidthMeters = 0.9f
                    minHeightMeters = 0.6f
                    canResize = true
                    canClose = true
                }
            }
        )

        Entity.createPanelEntity(R.id.panel_decks, Transform(Pose(Vector3(0.0f, 0.0f, -1.2f))))
        Entity.createPanelEntity(R.id.panel_review, Transform(Pose(Vector3(0.8f, 0.0f, -1.2f))))
    }
}
