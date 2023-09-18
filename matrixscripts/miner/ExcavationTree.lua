--basic implementation of a tree structure.<br>
--Note that this is a special implementation for the vein excavation and does not necessarily behave exactly as a normal tree would.
local M = {}

--[[
    instanciates an object of the tree type<br>
    @param node_x x coordinate of the node<br>
    @param node_y y coordinate of the node<br>
    @param node_z z coordinate of the node
]]
M.newInstance = function(node_x, node_y, node_z)
    return {
        --x coordinate of the node
        x = node_x,
        --y coordinate of the node
        y = node_y,
        --z coordinate of the node
        z = node_z,
        --[[
            queries the coordinates of the tree
            <ol>
                <li>@return x coordinate</li>
                <li>@return y coordinate</li>
                <li>@return z coordinate</li>
            </ol>
        ]]
        getCoordinates = function (self)
            return self.x, self.y, self.z
        end,
        --children of this node
        children = {},
        --[[
            parent node of this node<br>
            only gets set here so that it is clear the parameter is used (since it starts at nil)
        ]]
        parent = nil,
        --[[
            adds the given tree as a child<br>
            @param new_tree the node to make the new child
        ]]
        addChild = function (self, new_tree)
            new_tree.parent = self
            self.children[#self.children+1] = new_tree
        end,
        --[[
            checks whether this node is a leaf (has children)<br>
                @return true, if this node is a leaf; false otherwise
        ]]
        isLeaf = function (self)
            return #self.children == 0
        end,
        --[[
            checks if this node or a child contains a point with the given coordinates<br>
            @param search_x x coordinate of point to search for<br>
            @param search_y y coordinate of point to search for<br>
            @param search_z z coordinate of point to search for<br>
            @return true, if the point was found; false otherwise
        ]]
        contains = function (self, search_x, search_y, search_z)
            if self.x == search_x and self.y == search_y and self.z == search_z then
                return true
            end
            for i = 1, #self.children, 1 do
                if self.children[i]:contains(search_x, search_y, search_z) then
                    return true
                end
            end
            return false
        end,
        --[[
            checks how many nodes there are above this one<br>
            @return the amount of nodes above this one in the tree
        ]]
        currentDepth = function (self)
            local temp = self
            local counter = 0
            while not (temp.parent == nil) do
                counter = counter + 1
                temp = temp.parent
            end
            return counter
        end,
        --[[
            queries the top node of the tree<br>
            @return the top node
        ]]
        getFirstParent = function (self)
            local current_knot = self
            while not (current_knot.parent == nil) do
                current_knot = current_knot.parent
            end
            return current_knot
        end,
        --allows for object.class.newInstance()
        class = M
    }
end

return M