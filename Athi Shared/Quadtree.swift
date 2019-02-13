//
//  Quadtree.swift
//  Athi
//
//  Created by Marcus Mathiassen on 05/04/2018.
//  Copyright © 2018 Marcus Mathiassen. All rights reserved.
//

// swiftlint:disable identifier_name

import simd.vector_types // float2, float4

struct Rect {
    
    var min = float2(0, 0)
    var max = float2(0, 0)
    var color = float4(1, 1, 1, 1)

    init(min: float2, max: float2) {
        self.min = min
        self.max = max
    }

    func containsPoint(position: float2, radius: Float) -> Bool {
        if position.x - radius < max.x &&
            position.x + radius > min.x &&
            position.y - radius < max.y &&
            position.y + radius > min.y {
            return true
        }
        return false
    }
}

final class Quadtree {

    static var maxCapacityPerNode: Int { return 50 }
    static var maxDepth: Int { return 5 }
    static var data: [Collidable] = []

    var bounds: Rect
    var depth: Int = 0

    var hasSplit: Bool = false

    var indices: [Int32] = []

    var sw: Quadtree?
    var se: Quadtree?
    var nw: Quadtree?
    var ne: Quadtree?

    init(depth: Int, bounds: Rect) {
        self.depth = depth
        self.bounds = bounds

        indices.reserveCapacity(Quadtree.maxCapacityPerNode)
    }

    init(min: float2, max: float2) {
        bounds = Rect(min: min, max: max)
        indices.reserveCapacity(Quadtree.maxCapacityPerNode)
    }

    /**
     Splits this node into four quadrants
     */
    func split() {
        let min: float2 = bounds.min
        let max: float2 = bounds.max

        let x: Float = min.x
        let y: Float = min.y
        let width: Float = max.x - min.x
        let height: Float = max.y - min.y

        let w: Float = width * 0.5
        let h: Float = height * 0.5

        let SW = Rect(min: float2(x, y), max: float2(x + w, y + h))
        let SE = Rect(min: float2(x + w, y), max: float2(x + width, y + h))
        let NW = Rect(min: float2(x, y + h), max: float2(x + w, y + height))
        let NE = Rect(min: float2(x + w, y + h), max: float2(x + width, y + height))

        sw = Quadtree(depth: depth + 1, bounds: SW)
        se = Quadtree(depth: depth + 1, bounds: SE)
        nw = Quadtree(depth: depth + 1, bounds: NW)
        ne = Quadtree(depth: depth + 1, bounds: NE)

        hasSplit = true
    }

    /**
     Inserts all elements into the quadtree
     */
    func inputRange(range: ClosedRange<Int>) {
        for index in range.lowerBound ..< range.upperBound {
            insert(index)
        }
    }
    func setInputData(_ data: [Collidable]) {
        Quadtree.data = data
    }

    /**
     Returns true if this node contains the index
     */
    func contains(_ index: Int) -> Bool {
        return bounds.containsPoint(position: Quadtree.data[index].position, radius: Quadtree.data[index].size)
    }

    /**
     Inserts an index into the quadtree
     */
    func insert(_ index: Int) {
        // If this node has split add it to the children instead
        if hasSplit {
            if sw?.contains(index) ?? false { sw?.insert(index) }
            if se?.contains(index) ?? false { se?.insert(index) }
            if nw?.contains(index) ?? false { nw?.insert(index) }
            if ne?.contains(index) ?? false { ne?.insert(index) }
            return
        }

        // .. else add it here.
        indices.append(Int32(index))

        // Then if we've reached our max capacity..
        if indices.count > Quadtree.maxCapacityPerNode && depth < Quadtree.maxDepth {
            // ..split..
            split()

            //  ..and move the indices from this node to the new ones
            for index in indices {
                if sw?.contains(Int(index)) ?? false { sw?.insert(Int(index)) }
                if se?.contains(Int(index)) ?? false { se?.insert(Int(index)) }
                if nw?.contains(Int(index)) ?? false { nw?.insert(Int(index)) }
                if ne?.contains(Int(index)) ?? false { ne?.insert(Int(index)) }
            }

            // .. and clear this one out
            indices.removeAll()
        }
    }

    /**
     Returns all nodes that contains objects
     */
    func getNodesOfIndices(containerOfNodes: inout [[Int32]]) {
        if hasSplit {
            sw?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            se?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            nw?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            ne?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            return
        }

        if !indices.isEmpty {
            containerOfNodes.append(indices)
        }
    }
    
    /**
     Returns the neighbour nodes to the input object
     */
    func getNeighbours(containerOfNodes: inout [Int32], collidable: Collidable) {
        if hasSplit {
            if (sw?.bounds.containsPoint(position: collidable.position, radius: collidable.size)) ?? false {
                sw?.getNeighbours(containerOfNodes: &containerOfNodes, collidable: collidable)
            }
            if (se?.bounds.containsPoint(position: collidable.position, radius: collidable.size)) ?? false {
                se?.getNeighbours(containerOfNodes: &containerOfNodes, collidable: collidable)
            }
            if (nw?.bounds.containsPoint(position: collidable.position, radius: collidable.size)) ?? false {
                nw?.getNeighbours(containerOfNodes: &containerOfNodes, collidable: collidable)
            }
            if (ne?.bounds.containsPoint(position: collidable.position, radius: collidable.size)) ?? false {
                ne?.getNeighbours(containerOfNodes: &containerOfNodes, collidable: collidable)
            }
            return
        }

        if !indices.isEmpty {
            containerOfNodes.append(contentsOf: indices)
        }
    }

    /**
     Draws all the nodes
     */
    func getNodesBounds(container: inout [Rect], onlyOccupied: Bool = true) {

        if hasSplit {
            sw?.getNodesBounds(container: &container, onlyOccupied: onlyOccupied)
            se?.getNodesBounds(container: &container, onlyOccupied: onlyOccupied)
            nw?.getNodesBounds(container: &container, onlyOccupied: onlyOccupied)
            ne?.getNodesBounds(container: &container, onlyOccupied: onlyOccupied)
            return
        }

        if !indices.isEmpty && onlyOccupied {
            container.append(bounds)
        } else {
            container.append(bounds)
        }
    }

    /**
     Colors neighbour nodes to the input object
     */
    func colorNeighbours(position: float2, radius: Float, color: float4) {
        if hasSplit {
            if (sw?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                sw?.colorNeighbours(position: position, radius: radius, color: color) }
            if (se?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                se?.colorNeighbours(position: position, radius: radius, color: color) }
            if (nw?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                nw?.colorNeighbours(position: position, radius: radius, color: color) }
            if (ne?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                ne?.colorNeighbours(position: position, radius: radius, color: color) }
            return
        }
        bounds.color = color
    }
}

final class QuadtreeSoA {

    struct Rect {
        var min = float2(0)
        var max = float2(0)
        var color = float4(1)

        init(min: float2, max: float2) {
            self.min = min
            self.max = max
        }

        func containsPoint(position: float2, radius: Float) -> Bool {
            if position.x - radius < max.x &&
                position.x + radius > min.x &&
                position.y - radius < max.y &&
                position.y + radius > min.y {
                return true
            }
            return false
        }
    }

    static var maxCapacityPerNode: Int = 50
    static var maxDepth: Int = 5
    private static var positions: [float2] = []
    private static var radii: [Float] = []

    var bounds: Rect
    var depth: Int = 0

    var hasSplit: Bool = false

    var indices: [Int] = []

    var sw: QuadtreeSoA?
    var se: QuadtreeSoA?
    var nw: QuadtreeSoA?
    var ne: QuadtreeSoA?

    init(depth: Int, bounds: Rect) {
        self.depth = depth
        self.bounds = bounds

        indices.reserveCapacity(QuadtreeSoA.maxCapacityPerNode)
    }

    init(min: float2, max: float2) {
        bounds = Rect(min: min, max: max)
        indices.reserveCapacity(QuadtreeSoA.maxCapacityPerNode)
    }

    /**
     Splits this node into four quadrants
     */
    func split() {
        let min: float2 = bounds.min
        let max: float2 = bounds.max

        let x: Float = min.x
        let y: Float = min.y
        let width: Float = max.x - min.x
        let height: Float = max.y - min.y

        let w: Float = width * 0.5
        let h: Float = height * 0.5

        let SW = Rect(min: float2(x, y), max: float2(x + w, y + h))
        let SE = Rect(min: float2(x + w, y), max: float2(x + width, y + h))
        let NW = Rect(min: float2(x, y + h), max: float2(x + w, y + height))
        let NE = Rect(min: float2(x + w, y + h), max: float2(x + width, y + height))

        sw = QuadtreeSoA(depth: depth + 1, bounds: SW)
        se = QuadtreeSoA(depth: depth + 1, bounds: SE)
        nw = QuadtreeSoA(depth: depth + 1, bounds: NW)
        ne = QuadtreeSoA(depth: depth + 1, bounds: NE)

        hasSplit = true
    }

    /**
     Inserts all elements into the quadtree
     */
    func inputRange(range: ClosedRange<Int>) {
        for id in range.lowerBound ..< range.upperBound {
            insert(id)
        }
    }
    func setInputData(positions: [float2], radii: [Float]) {
        QuadtreeSoA.positions = positions
        QuadtreeSoA.radii = radii
    }

    /**
     Returns true if this node contains the index
     */
    func contains(_ id: Int) -> Bool {
        return bounds.containsPoint(position: QuadtreeSoA.positions[id], radius: QuadtreeSoA.radii[id])
    }

    /**
     Inserts an index into the quadtree
     */
    func insert(_ id: Int) {
        // If this node has split add it to the children instead
        if hasSplit {
            if sw?.contains(id) ?? false { sw?.insert(id) }
            if se?.contains(id) ?? false { se?.insert(id) }
            if nw?.contains(id) ?? false { nw?.insert(id) }
            if ne?.contains(id) ?? false { ne?.insert(id) }
            return
        }

        // .. else add it here.
        indices.append(id)

        // Then if we've reached our max capacity..
        if indices.count > QuadtreeSoA.maxCapacityPerNode && depth < QuadtreeSoA.maxDepth {
            // ..split..
            split()

            //  ..and move the indices from this node to the new ones
            for index in indices {
                if sw?.contains(index) ?? false { sw?.insert(index) }
                if se?.contains(index) ?? false { se?.insert(index) }
                if nw?.contains(index) ?? false { nw?.insert(index) }
                if ne?.contains(index) ?? false { ne?.insert(index) }
            }

            // .. and clear this one out
            indices.removeAll()
        }
    }

    /**
     Returns all nodes that contains objects
     */
    func getNodesOfIndices(containerOfNodes: inout [[Int]]) {
        if hasSplit {
            sw?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            se?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            nw?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            ne?.getNodesOfIndices(containerOfNodes: &containerOfNodes)
            return
        }

        if !indices.isEmpty {
            containerOfNodes.append(indices)
        }
    }

    /**
     Returns the neighbour nodes to the input object
     */
    func getNeighbours(containerOfNodes: inout [[Int]], position: float2, radius: Float) {
        if hasSplit {
            if (sw?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                sw?.getNeighbours(containerOfNodes: &containerOfNodes, position: position, radius: radius) }
            if (se?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                se?.getNeighbours(containerOfNodes: &containerOfNodes, position: position, radius: radius) }
            if (nw?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                nw?.getNeighbours(containerOfNodes: &containerOfNodes, position: position, radius: radius) }
            if (ne?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                ne?.getNeighbours(containerOfNodes: &containerOfNodes, position: position, radius: radius) }
            return
        }

        if !indices.isEmpty {
            containerOfNodes.append(indices)
        }
    }

    /**
     Colors neighbour nodes to the input object
     */
    func colorNeighbours(position: float2, radius: Float, color: float4) {
        if hasSplit {
            if (sw?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                sw?.colorNeighbours(position: position, radius: radius, color: color) }
            if (se?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                se?.colorNeighbours(position: position, radius: radius, color: color) }
            if (nw?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                nw?.colorNeighbours(position: position, radius: radius, color: color) }
            if (ne?.bounds.containsPoint(position: position, radius: radius)) ?? false {
                ne?.colorNeighbours(position: position, radius: radius, color: color) }
            return
        }
        bounds.color = color
    }
}
