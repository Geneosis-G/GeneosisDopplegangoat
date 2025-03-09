class Dopplegangoat extends GGMutator;

var array<DopplegangoatComponent> mComponents;
var int mNextModel;

/**
 * See super.
 */
function ModifyPlayer(Pawn Other)
{
	local GGGoat goat;
	local DopplegangoatComponent nightComp;

	super.ModifyPlayer( other );

	goat = GGGoat( other );
	if( goat != none )
	{
		nightComp=DopplegangoatComponent(GGGameInfo( class'WorldInfo'.static.GetWorldInfo().Game ).FindMutatorComponent(class'DopplegangoatComponent', goat.mCachedSlotNr));
		if(nightComp != none && mComponents.Find(nightComp) == INDEX_NONE)
		{
			mComponents.AddItem(nightComp);
			if(mComponents.Length == 1)
			{
				InitDopplegangoatInteraction();
			}
		}
	}
}

simulated event Tick( float delta )
{
	local int i;

	for( i = 0; i < mComponents.Length; i++ )
	{
		mComponents[ i ].Tick( delta );
	}
	super.Tick( delta );
}

function InitDopplegangoatInteraction()
{
	local DopplegangoatInteraction di;

	di = new class'DopplegangoatInteraction';
	di.InitDopplegangoatInteraction(self);
	GetALocalPlayerController().Interactions.AddItem(di);
}

function SelectModel(string modelName)
{
	local int i;
	for(i=0 ; i<mComponents[0].mFullMeshes.Length ; i++ )
	{
		if(Caps(mComponents[0].mFullMeshes[i].mName) == Caps(modelName))
		{
			mNextModel=i;
			WorldInfo.Game.Broadcast(self, modelName $ " model found, next character to change model will have it");
			return;
		}
	}

	WorldInfo.Game.Broadcast(self, modelName $ " model not found");
}

function ListModelsFrom(int index)
{
	local int i, j;
	for(i=index ; i<index+20 ; i++ )
	{
		j=i;
		if(i >= mComponents[0].mFullMeshes.Length)
		{
			j=i-mComponents[0].mFullMeshes.Length;
		}
		WorldInfo.Game.Broadcast(self, j $ ":" $ mComponents[0].mFullMeshes[j].mName);
	}
}

DefaultProperties
{
	mMutatorComponentClass=class'DopplegangoatComponent'
	mNextModel=-1
}